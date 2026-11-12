"""扫描周期仿真器：把 ST 源码解释执行，逐周期比对期望输出。

为什么用"解释执行"而不是"生成 Python 再跑"
------------------------------------------
生成代码需要做代码生成与变量映射，出 bug 时很难判断是生成器错还是被测代码错。
这一层直接按 AST 求值：语义与 IEC 61131-3 扫描周期一致（先算完整个 FB 体，
输出在下个周期才被外部读到——我们只在周期末尾断言输出），出错能精确定位到行。

对齐的 IEC 语义
---------------
* **标识符不区分大小写**：``kikc`` 与 ``KIKC`` 是同一个变量；
* **整数除法向零截断**：``7/2 = 3``、``-7/2 = -3``（不是 Python 的 -4）；
* **MOD 符号跟随被除数**：``-7 MOD 2 = -1``；
* **短路求值不成立**：IEC 的 AND/OR 不保证短路，这里按顺序求值两边；
* **VAR_OUTPUT 保持**：未被赋值的输出保持上一周期的值（不是清零）；
* **VAR 保持**：静态变量跨周期保持，这是边沿检测、计时器的基础；
* **数组按题面下界索引**：``ARRAY[1..5]`` 的下界是 1，不是 0。

安全阀
------
被测代码可能写出死循环（``WHILE TRUE``）。解释器对每周期语句数与循环
深度设上限，超限抛 ``SimulationTimeout``，算作答错而不是把整批实验卡死。
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, field
from typing import Any

from .frontend import Decl, Node, POU, compile_st
from .typecheck import typecheck


class SimulationTimeout(Exception):
    """单周期执行超过语句/循环预算。"""


class SimError(Exception):
    """运行期错误：除零、下标越界、类型误用等。"""

    def __init__(self, msg: str, line: int = 0):
        super().__init__(msg)
        self.line = line


@dataclass
class ArrayValue:
    """IEC 数组：显式保存下界，因为 ST 的数组不一定是 1 基。"""

    lo: int
    hi: int
    items: list[Any]

    def get(self, idx: int, line: int = 0) -> Any:
        if not (self.lo <= idx <= self.hi):
            raise SimError(f"数组下标 {idx} 越界 [{self.lo}..{self.hi}]", line)
        return self.items[idx - self.lo]

    def set(self, idx: int, value: Any, line: int = 0) -> None:
        if not (self.lo <= idx <= self.hi):
            raise SimError(f"数组下标 {idx} 越界 [{self.lo}..{self.hi}]", line)
        self.items[idx - self.lo] = value

    def copy(self) -> "ArrayValue":
        return ArrayValue(self.lo, self.hi, [_deep_copy(d) for d in self.items])

    # 用 ``x.data`` 的老写法也要继续能用，免得改一处漏一处
    @property
    def data(self) -> list[Any]:
        return self.items


@dataclass
class VariantValue:
    """VARIANT：装着一个具体类型值的泛型引用。

    这是 STBench 对课程题的解释器表示。调用方提供的值或数组保存在 value 中，
    数组边界由实际绑定决定。tag 为解释器附带的类型信息；目标平台能否接受同名
    ST 声明，需要使用该平台编译器和实际调用接口单独验收。
    """

    value: Any = None
    tag: str = ""  # 具体类型名，如 "DINT" / "ARRAY[1..8] OF INT"

    def __bool__(self) -> bool:
        return self.value is not None

    def __repr__(self) -> str:
        inner = self.value
        if isinstance(inner, ArrayValue):
            return f"VARIANT<{self.tag}>({inner!r})"
        return f"VARIANT<{self.tag}>({inner!r})"


@dataclass
class StructValue:
    type_name: str
    values: dict[str, Any] = field(default_factory=dict)

    def copy(self) -> "StructValue":
        return StructValue(self.type_name, {k: _deep_copy(v) for k, v in self.values.items()})

    def __repr__(self) -> str:
        return f"{self.type_name}{self.values}"


def _deep_copy(v: Any) -> Any:
    if isinstance(v, (ArrayValue, StructValue)):
        return v.copy()
    return v


def _infer_tag(v: Any) -> str:
    """反推 VARIANT 里装的是什么，用于没有旧 tag 可继承时。"""
    if isinstance(v, bool):
        return "BOOL"
    if isinstance(v, int):
        return "DINT"
    if isinstance(v, float):
        return "REAL"
    if isinstance(v, str):
        return "STRING"
    if isinstance(v, ArrayValue):
        elem = _infer_tag(v.items[0]) if v.items else "DINT"
        return f"ARRAY[{v.lo}..{v.hi}] OF {elem}"
    if isinstance(v, StructValue):
        return v.type_name
    return "VARIANT"


# --------------------------------------------------------------------------
# 类型工具
# --------------------------------------------------------------------------

_INT_TYPES = {
    "SINT": (8, True), "INT": (16, True), "DINT": (32, True), "LINT": (64, True),
    "USINT": (8, False), "UINT": (16, False), "UDINT": (32, False), "ULINT": (64, False),
    "BYTE": (8, False), "WORD": (16, False), "DWORD": (32, False), "LWORD": (64, False),
}
_REAL_TYPES = {"REAL", "LREAL"}
_BOOL_TYPES = {"BOOL"}


def _base_type(dtype: str) -> str:
    """剥掉 ARRAY 外壳，返回元素类型名（大写）。

    ⚠️ 这里**不能**直接 ``dtype.upper()``：IEC 标识符大小写不敏感，但
    ``self.structs`` 的键是原样存储的（``ST_Recipe``）。一 upper 就变成
    ``ST_RECIPE``，查表落空，结构体退回整数处理——现象是"结构体字段读不到"，
    而报错信息完全指向别处，极难定位。所以按大小写不敏感的方式解析结构体名。
    """
    up = dtype.upper()
    if " OF " in up:
        return up.split(" OF ", 1)[1].strip()
    return up


def _elem_type(dtype: str, structs: dict[str, Any] | None = None) -> str:
    """返回数组元素类型，并把结构体名还原成 ``structs`` 里的真实大小写。"""
    elem = _base_type(dtype)
    for k in (structs or {}):
        if k.upper() == elem.upper():
            return k
    return elem


def _array_bounds(dtype: str) -> tuple[int, int] | None:
    m = re.search(r"\[\s*(-?\d+)\s*\.\.\s*(-?\d+)\s*\]", dtype)
    return (int(m.group(1)), int(m.group(2))) if m else None


def _wrap_int(value: int, dtype: str) -> int:
    """按目标整数类型做定宽回绕（CODESYS 编译后就是这样）。"""
    spec = _INT_TYPES.get(dtype.upper())
    if spec is None:
        return value
    bits, signed = spec
    mask = (1 << bits) - 1
    v = int(value) & mask
    if signed and v >= (1 << (bits - 1)):
        v -= 1 << bits
    return v


def default_for(dtype: str, structs: dict[str, Any]) -> Any:
    """按类型造初值。数组按题面下界建。"""
    up = dtype.upper()
    if up == "VARIANT":
        # 泛型引用：具体类型和容量由调用方在运行时决定，见 VariantValue
        return VariantValue()
    if up in _BOOL_TYPES:
        return False
    if up in _REAL_TYPES:
        return 0.0
    if up in _INT_TYPES:
        return 0
    if up in ("STRING", "WSTRING"):
        return ""
    if up in ("R_TRIG", "F_TRIG"):
        return StructValue(up, {"CLK":False,"Q":False,"_M":up == "F_TRIG"})
    if up == "TON":
        return StructValue("TON", {"IN":False, "PT":0, "Q":False, "ET":0, "_start_ms":None})
    if up in ("TIME", "LTIME"):
        return 0
    bounds = _array_bounds(dtype)
    if bounds is not None or up.startswith("ARRAY["):
        lo, hi = bounds or (0, -1)
        elem = _elem_type(dtype, structs)
        return ArrayValue(lo, hi, [default_for(elem, structs) for _ in range(hi - lo + 1)])
    # 结构体
    st = next((value for name, value in structs.items() if name.lower() == dtype.lower()), None)
    if st is not None:
        if hasattr(st, 'members'):
            return st.default
        return StructValue(dtype, {f: default_for(t, structs) for f, t in st.fields.items()})
    # 未知类型：当整数处理，但记 NULL 方便定位
    return 0


def _tag_of(v: Any) -> str:
    """从一个 Python 运行时值反推 IEC 类型名，用于 VARIANT 的类型标签。"""
    if isinstance(v, bool):
        return "BOOL"
    if isinstance(v, float):
        return "REAL"
    if isinstance(v, str):
        return "STRING"
    if isinstance(v, ArrayValue):
        if v.items:
            return f"ARRAY[{v.lo}..{v.hi}] OF {_tag_of(v.items[0])}"
        return f"ARRAY[{v.lo}..{v.hi}] OF DINT"
    if isinstance(v, StructValue):
        return v.type_name
    if isinstance(v, int):
        return "DINT"
    return "ANY"


def coerce(value: Any, dtype: str, structs: dict[str, Any] | None = None) -> Any:
    """把外部输入强制成声明的类型，模拟 PLC 的输入映射。

    **数组必须转成 ArrayValue**：测试表里写 ``[1,2,...,8]`` 是最自然的写法，
    但如果原样存成 Python list，被测代码里的 ``values[i]``（按 IEC 下界索引）
    就会拿到错误元素，甚至直接报"不是数组"。结构体同理。
    """
    structs = structs or {}
    up = dtype.upper()

    if up == "VARIANT":
        # 泛型引用：具体类型由调用方给的 Python 值反推。
        # list -> ARRAY[1..n] OF <元素类型>，其中 n = 实际长度（题面的"容量"）。
        if isinstance(value, VariantValue):
            return value
        if isinstance(value, (list, tuple)):
            seq = list(value)
            elem_tag = "DINT"
            for x in seq:
                elem_tag = _tag_of(x)
                break
            n = max(len(seq), 1)
            arr = ArrayValue(1, n, [coerce(x, elem_tag, structs) for x in seq])
            return VariantValue(arr, f"ARRAY[1..{n}] OF {elem_tag}")
        return VariantValue(value, _tag_of(value))

    bounds = _array_bounds(dtype)
    if bounds is not None or up.startswith("ARRAY["):
        lo, hi = bounds or (0, -1)
        elem = _elem_type(dtype, structs)
        if isinstance(value, ArrayValue):
            return value
        if bounds is None and re.search(r"\[\s*\*\s*\]", up):
            if isinstance(value, (list, tuple)):
                lo, seq = 1, value
            elif (isinstance(value, dict) and set(value) == {"lower", "values"}
                  and type(value["lower"]) is int and isinstance(value["values"], (list, tuple))):
                lo, seq = value["lower"], value["values"]
            else:
                raise SimError("ARRAY[*] requires a caller array, optionally with explicit lower/values")
            hi = lo + len(seq) - 1
            if not seq or not (-2147483648 <= lo <= hi <= 2147483647):
                raise SimError("Caller array must have nonempty DINT bounds")
        else:
            seq = list(value) if isinstance(value, (list, tuple)) else []
        items = []
        for i in range(hi - lo + 1):
            raw = seq[i] if i < len(seq) else default_for(elem, structs)
            items.append(coerce(raw, elem, structs))
        return ArrayValue(lo, hi, items)

    st = next((value for name, value in structs.items() if name.lower() == dtype.lower()), None)
    if st is not None:
        if hasattr(st, 'members'):
            if isinstance(value, str):
                member = value.rsplit('.', 1)[-1].lower()
                found = [v for k, v in st.members.items() if k.lower() == member]
                if not found:
                    raise SimError('未声明的枚举输入值')
                return found[0]
            return _wrap_int(int(value), st.base_type)
        if isinstance(value, StructValue):
            return value
        given = value if isinstance(value, dict) else {}
        # 字段名大小写不敏感地匹配
        lower = {str(k).lower(): v for k, v in given.items()}
        return StructValue(
            dtype,
            {f: coerce(lower.get(f.lower(), default_for(t, structs)), t, structs)
             for f, t in st.fields.items()},
        )

    if up in _BOOL_TYPES:
        if isinstance(value, str):
            return value.strip().upper() in ("TRUE", "1", "YES")
        return bool(value)
    if up in _REAL_TYPES:
        return float(value)
    if up in _INT_TYPES:
        return _wrap_int(int(value), up)
    return value


# --------------------------------------------------------------------------
# 仿真器
# --------------------------------------------------------------------------


@dataclass
class SimOutcome:
    ok: bool
    cycles_run: int = 0
    failure_cycle: int | None = None
    failure_var: str = ""
    expected: Any = None
    actual: Any = None
    message: str = ""
    # 记录每个周期的完整快照，便于写报告时举反例
    trace: list[dict[str, Any]] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "cycles_run": self.cycles_run,
            "failure_cycle": self.failure_cycle,
            "failure_var": self.failure_var,
            "expected": self.expected,
            "actual": self.actual,
            "message": self.message,
        }


def _duration_cast(value, source_type, target_type):
    pair = ((source_type or "").upper(), (target_type or "").upper())
    if pair == ("TIME", "LTIME"):
        return value * 1000000
    if pair == ("LTIME", "TIME"):
        return value // 1000000
    return value


class Interpreter:
    MAX_STEPS_PER_CYCLE = 200_000
    MAX_LOOP_ITER = 20_000
    MAX_CALL_DEPTH = 8

    def __init__(self, pou: POU, structs: dict[str, Any]):
        self.clock_ms = None
        self.pou = pou
        self.structs = structs
        self.mem: dict[str, Any] = {}
        self.types: dict[str, str] = {}
        self.sections: dict[str, str] = {}
        self.steps = 0
        self.depth = 0
        self.enum_constants = {}
        self.enum_types = {name.lower(): value for name, value in structs.items() if hasattr(value, 'members')}
        for enum in self.enum_types.values():
            for member, value in enum.members.items():
                self.enum_constants[(enum.name + '.' + member).lower()] = value
                key = member.lower()
                if not enum.qualified_only and sum(any(m.lower() == key for m in e.members) for e in self.enum_types.values() if not e.qualified_only) == 1:
                    self.enum_constants[key] = value

        for d in pou.decls:
            self.types[d.name.lower()] = d.data_type
            self.sections[d.name.lower()] = d.section
            self.mem[d.name.lower()] = default_for(d.data_type, structs)
        # 初值
        for d in pou.decls:
            if d.init is not None:
                try:
                    self.mem[d.name.lower()] = _duration_cast(self.eval(d.init), d.init.typ, d.data_type)
                except (SimError, SimulationTimeout):
                    pass

    # ---- 外部接口：读写变量 ----
    def reset(self) -> None:
        """回到上电初值（跨用例复用同一个 FB 实例时用）。"""
        self.clock_ms = None
        for d in self.pou.decls:
            self.mem[d.name.lower()] = default_for(d.data_type, self.structs)
        for d in self.pou.decls:
            if d.init is not None:
                try:
                    self.mem[d.name.lower()] = _duration_cast(self.eval(d.init), d.init.typ, d.data_type)
                except (SimError, SimulationTimeout):
                    pass

    def set_var(self, name: str, value: Any) -> None:
        key = name.lower()
        if key not in self.mem:
            raise SimError(f"接口里没有变量 {name!r}")
        self.mem[key] = coerce(value, self.types[key], self.structs)

    @staticmethod
    def _unwrap(v: Any) -> Any:
        """VARIANT 透明取壳。

        泛型引用在语法上是"一个变量"，用户代码里写 ``buffer[i]`` 而不是
        ``buffer.value[i]``。所以求值到 VARIANT 时必须剥掉壳子，否则所有
        泛型题都要写成 .value 形式，与题面和 IEC 习惯都不符。
        """
        while isinstance(v, VariantValue):
            v = v.value
        return v
        # 线圈/输出区可以在每次扫描开头被外部重写，所以记一下"外部注入"
        # （仅用于调试，不影响求值）

    def get_var(self, name: str) -> Any:
        key = name.lower()
        if key not in self.mem:
            raise SimError(f"接口里没有变量 {name!r}")
        return self.mem[key]

    # ---- 枚举成员：ST_Pump.RunComd 这类类型名.成员 的写法 ----
    ENUM_MEMBERS = {
        "RETVAL", "STATUS", "ERROR", "RUNCOMD", "SELECTION", "PRIORITY",
    }

    # ---- 执行一个扫描周期 ----
    def scan(self, scan_interval_ms: int | None = None) -> None:
        if scan_interval_ms is not None:
            if type(scan_interval_ms) is not int or scan_interval_ms < 0:
                raise SimError("Invalid scan interval (integer milliseconds required)")
            self.clock_ms = 0 if self.clock_ms is None else self.clock_ms + scan_interval_ms
        else:
            self.clock_ms = None
        self.steps = 0
        for st in self.pou.body:
            self.exec_stmt(st)

    def exec_stmt(self, st: Node) -> None:
        self.steps += 1
        if self.steps > self.MAX_STEPS_PER_CYCLE:
            raise SimulationTimeout("单周期语句数超过上限，疑似死循环")

        k = st.kind
        if k == "nop":
            return
        if k == "assign":
            target, value = st.args
            v = _duration_cast(self.eval(value), value.typ, target.typ)
            self.assign(target, v, st.line)
            return
        if k == "if":
            if self._truthy(self.eval(st.args[0])):
                for s in st.stmts:
                    self.exec_stmt(s)
                return
            for cond, body in st.elifs:
                if self._truthy(self.eval(cond)):
                    for s in body:
                        self.exec_stmt(s)
                    return
            for s in st.else_body:
                self.exec_stmt(s)
            return
        if k == "case":
            sel = self.eval(st.args[0])
            for label, body in st.elifs:
                hit = False
                for lb in label.args:
                    if self._case_match(lb, sel):
                        hit = True
                        break
                if hit:
                    for s in body:
                        self.exec_stmt(s)
                    return
            for s in st.else_body:
                self.exec_stmt(s)
            return
        if k == "for":
            var_name = st.tok.value
            start = int(self.eval(st.args[0]))
            end = int(self.eval(st.args[1]))
            step = int(self.eval(st.args[2])) if len(st.args) > 2 else 1
            if step == 0:
                raise SimError("FOR 循环步长为 0", st.line)
            n = 0
            i = start
            while (i <= end) if step > 0 else (i >= end):
                n += 1
                if n > self.MAX_LOOP_ITER:
                    raise SimulationTimeout("FOR 循环次数超过上限，疑似死循环")
                self.mem[var_name.lower()] = _wrap_int(i, self.types.get(var_name.lower(), "INT"))
                try:
                    for s in st.stmts:
                        self.exec_stmt(s)
                except _BreakLoop:
                    break
                i += step
            return
        if k == "while":
            n = 0
            while self._truthy(self.eval(st.args[0])):
                n += 1
                if n > self.MAX_LOOP_ITER:
                    raise SimulationTimeout("WHILE 循环超过上限，疑似死循环")
                try:
                    for s in st.stmts:
                        self.exec_stmt(s)
                except _BreakLoop:
                    break
            return
        if k == "repeat":
            n = 0
            while True:
                n += 1
                if n > self.MAX_LOOP_ITER:
                    raise SimulationTimeout("REPEAT 循环超过上限，疑似死循环")
                try:
                    for s in st.stmts:
                        self.exec_stmt(s)
                except _BreakLoop:
                    break
                if self._truthy(self.eval(st.args[0])):
                    break
            return
        if k == "exit":
            raise _BreakLoop()
        if k == "return":
            return
        if k in ("call", "exprstmt"):
            self.eval(st)
            return
        raise SimError(f"未知语句类型 {k}", st.line)

    def _case_match(self, label: Node, sel: Any) -> bool:
        if label.kind == "range":
            lo = self.eval(label.args[0])
            hi = self.eval(label.args[1])
            return lo <= sel <= hi
        return self.eval(label) == sel

    # ---- 赋值 ----
    def assign(self, target: Node, value: Any, line: int) -> None:
        if target.kind == "name":
            key = target.tok.value.lower()
            dtype = self.types.get(key, "INT")
            if isinstance(value, str) and dtype.upper() not in ("STRING", "WSTRING"):
                pass
            # VARIANT 形参被整个赋值时（如 FIFO 的 ``item := buffer[head]``），
            # 要把值**装进盒子**并更新 tag，而不是当成未知类型原样塞进去。
            # 否则 _unwrap 会摸到一个裸值，读出来的类型判断全乱套。
            if dtype.upper() == "VARIANT":
                old = self.mem.get(key)
                tag = old.tag if isinstance(old, VariantValue) and old.tag else _infer_tag(value)
                self.mem[key] = VariantValue(value=_deep_copy(value), tag=tag)
                return
            self.mem[key] = self._cast(value, dtype)
            return
        if target.kind == "member":
            base = self._read_ref(target.args[0], line)
            field_name = target.tok.value
            if isinstance(base, StructValue):
                key = self._match_field(base, field_name, line)
                if base.type_name in ("TON", "R_TRIG", "F_TRIG"):
                    if key not in (("IN", "PT") if base.type_name == "TON" else ("CLK",)):
                        raise SimError("Invalid timer input: " + field_name, line)
                    base.values[key] = value
                    return
                base.values[key] = self._cast(value, self.structs[base.type_name].fields[key])
                return
            if isinstance(base, int) and field_name.isdigit():
                bit=int(field_name);width={"BYTE":8,"WORD":16,"DWORD":32,"LWORD":64}.get(target.args[0].typ,0)
                if not 0 <= bit < width:raise SimError("Bit selector out of range", line)
                updated=(base | (1 << bit)) if value else (base & ~(1 << bit))
                self.assign(target.args[0],updated,line);return
            raise SimError(f"无法给 {field_name} 赋值：基对象不是结构体", line)
        if target.kind == "index":
            base = self._read_ref(target.args[0], line)
            idx = int(self.eval(target.args[1]))
            if isinstance(base, ArrayValue):
                elem_type = _elem_type(
                    self.types.get(self._root_name(target), "ARRAY[0..0] OF INT"),
                    self.structs,
                )
                base.set(idx, self._cast(value, elem_type), line)
                return
            raise SimError("下标赋值的目标不是数组", line)
        raise SimError("赋值目标不合法", line)

    def _match_field(self, sv: StructValue, name: str, line: int) -> str:
        if name in sv.values:
            return name
        for k in sv.values:
            if k.lower() == name.lower():
                return k
        raise SimError(f"结构体 {sv.type_name} 没有字段 {name!r}", line)

    def _cast(self, value: Any, dtype: str) -> Any:
        up = dtype.upper()
        if dtype.lower() in self.enum_types:
            return _wrap_int(int(value), self.enum_types[dtype.lower()].base_type)
        if up in _BOOL_TYPES:
            return bool(value)
        if up in _REAL_TYPES:
            return float(value) if not isinstance(value, bool) else (1.0 if value else 0.0)
        if up in _INT_TYPES:
            if isinstance(value, bool):
                return 1 if value else 0
            return _wrap_int(int(value), up)
        return value

    def _root_name(self, node: Node) -> str:
        while node.kind in ("member", "index") and node.args:
            node = node.args[0]
        return node.tok.value.lower() if node.tok else ""

    # ---- 读取引用（数组/结构体做浅引用，保证写回生效） ----
    def _read_ref(self, node: Node, line: int) -> Any:
        if node.kind == "name":
            key = node.tok.value.lower()
            if key not in self.mem:
                raise SimError(f"未定义变量 {node.tok.value!r}", line)
            # VARIANT 是"装着数组的盒子"：下标/字段访问要作用在盒子里那个真数组上，
            # 否则 ``buffer[1] := x`` 会落到盒子上而写不回原数组。
            return self._unwrap(self.mem[key])
        if node.kind == "member":
            base = self._unwrap(self._read_ref(node.args[0], line))
            if isinstance(base, StructValue):
                return base.values[self._match_field(base, node.tok.value, line)]
            if isinstance(base,int) and node.tok.value.isdigit():
                bit=int(node.tok.value);width={"BYTE":8,"WORD":16,"DWORD":32,"LWORD":64}.get(node.args[0].typ,0)
                if not 0 <= bit < width:raise SimError("Bit selector out of range",line)
                return bool((base >> bit) & 1)
            raise SimError(f"{node.tok.value} 不是结构体字段", line)
        if node.kind == "index":
            base = self._unwrap(self._read_ref(node.args[0], line))
            idx = int(self.eval(node.args[1]))
            if isinstance(base, ArrayValue):
                return base.get(idx, line)
            raise SimError("下标访问的目标不是数组", line)
        if node.kind == "string":
            return node.tok.value
        return self._unwrap(self.eval(node))

    # ---- 表达式求值 ----
    def eval(self, node: Node) -> Any:
        self.steps += 1
        if self.steps > self.MAX_STEPS_PER_CYCLE:
            raise SimulationTimeout("单周期求值次数超限，疑似死循环")
        k = node.kind

        if k == "num":
            t = node.tok
            value=t.num if t and t.num is not None else 0
            return coerce(value,t.literal_type,self.structs) if t and t.literal_type else value
        if k == "str":
            return node.tok.value if node.tok else ""
        if k == "bool":
            return node.tok.value.upper() == "TRUE"

        if k == "name":
            name = node.tok.value
            key = name.lower()
            if key in self.mem:
                return self._unwrap(self.mem[key])
            if key in self.enum_constants:
                return self.enum_constants[key]
            # ARRAY[*] 这类边界函数用到的类型名，不参与取值
            raise SimError(f"未定义变量 {name!r}", node.line)

        if k == "member":
            base_node = node.args[0]
            field = node.tok.value
            if base_node.kind == 'name' and base_node.tok.value.lower() not in self.mem:
                qualified = (base_node.tok.value + '.' + field).lower()
                if qualified in self.enum_constants:
                    return self.enum_constants[qualified]
            # 枚举式写法：ST_Pump.RunComd / RetVal.OK —— 基名不是变量就当枚举成员
            if base_node.kind == "name" and base_node.tok.value.lower() not in self.mem:
                return field
            base = self.eval(base_node)
            if isinstance(base, StructValue):
                return base.values[self._match_field(base, field, node.line)]
            if isinstance(base, ArrayValue):
                raise SimError(f"数组没有字段 {field}", node.line)
            if isinstance(base,int) and field.isdigit():
                bit=int(field);width={"BYTE":8,"WORD":16,"DWORD":32,"LWORD":64}.get(base_node.typ,0)
                if not 0 <= bit < width:raise SimError("Bit selector out of range",node.line)
                return bool((base >> bit) & 1)
            raise SimError(f"{field} 不是结构体字段", node.line)

        if k == "index":
            base = self.eval(node.args[0])
            if isinstance(base, str):
                # IEC 61131-3：S[1] 取单字符（1 基），S[1..n] 取子串（闭区间）。
                # 空串或越界都返回空串，和多数 PLC 的宽松行为一致。
                if node.args[1].kind == "range":
                    lo = int(self.eval(node.args[1].args[0]))
                    hi = int(self.eval(node.args[1].args[1]))
                    if lo < 1 or hi < lo:
                        return ""
                    return base[lo - 1:hi]
                i = int(self.eval(node.args[1]))
                if i < 1 or i > len(base):
                    return ""
                return base[i - 1]
            idx = int(self.eval(node.args[1]))
            if isinstance(base, ArrayValue):
                return base.get(idx, node.line)
            raise SimError("下标访问的目标不是数组或字符串", node.line)

        if k == "unop":
            op = (node.tok.value if node.tok else "").upper()
            v = self.eval(node.args[0])
            if op == "NOT":
                # BOOL 取逻辑非；整数（WORD/DWORD/INT）取按位补码，与 IEC 一致
                if isinstance(v, bool) or v is None:
                    return not self._truthy(v)
                if isinstance(v, float):
                    raise SimError("NOT 不能用于 REAL", node.line)
                return ~int(v) & 0xFFFFFFFF
            if op == "-":
                return -v
            return +v

        if k == "binop":
            op = node.tok.value.upper()
            # IEC 不保证短路，按序求值两边。
            # 注意：不要在这里把两侧提前 _truthy()——AND/OR/XOR 在整数上是
            # 按位运算，提前转布尔会把 `(value SHL 4) OR (value SHR 28)`
            # 压成 0/1，位操作类程序会静默算出错误结果。交给 _binop 按类型分流。
            l = self.eval(node.args[0])
            r = self.eval(node.args[1])
            types = tuple((arg.typ or "").upper() for arg in node.args)
            if types == ("TIME", "LTIME"):
                l *= 1000000
            elif types == ("LTIME", "TIME"):
                r *= 1000000
            return self._binop(op, l, r, node.line)

        if k == "call":
            return self._call(node)

        raise SimError(f"无法求值的表达式类型 {k}", node.line)

    def _binop(self, op: str, l: Any, r: Any, line: int) -> Any:
        if op == "&":
            return f"{l}{r}"
        if op in ("SHL", "SHR", "ROL", "ROR"):
            # IEC 61131-3 中缀移位。DWORD 按 32 位无符号处理（位操作题的常见载体），
            # 右移用逻辑右移（补 0）而非算术右移——这是 61131-3 的规定，
            # 也是位边沿检测能成立的前提（否则负数右移会带进 1）。
            if isinstance(l, bool) or isinstance(r, bool):
                l, r = int(bool(l)), int(bool(r))
            if isinstance(l, float) or isinstance(r, float):
                raise SimError(f"{op} 的操作数必须是整数", line)
            shift = int(r)
            if shift < 0:
                raise SimError(f"{op} 的移位量不能为负：{shift}", line)
            bits = 32 if not (-2 ** 31 <= int(l) < 2 ** 31) else 32
            base = int(l) & (2 ** bits - 1)
            if op == "SHL":
                return (base << shift) & (2 ** bits - 1)
            if op == "SHR":
                return base >> shift
            shift %= bits
            if op == "ROL":
                return ((base << shift) | (base >> (bits - shift))) & (2 ** bits - 1)
            return ((base >> shift) | (base << (bits - shift))) & (2 ** bits - 1)
        if op in ("AND", "OR", "XOR"):
            # IEC 61131-3：AND/OR/XOR 是二义的——BOOL 上做逻辑，整数上做按位。
            # 「退化成整数」曾经有坑：`return l and r` 在左操作数是 INT 时
            # 会把整个条件变成整数 0/1，只要 count != 0 就恒为真，逻辑被静默篡改。
            # 现在按操作数类型分流：任一侧是 bool → 逻辑；两侧都是整数 → 按位。
            l_bool = isinstance(l, bool)
            r_bool = isinstance(r, bool)
            if l_bool or r_bool:
                if op == "AND":
                    return bool(l) and bool(r)
                if op == "OR":
                    return bool(l) or bool(r)
                return bool(l) != bool(r)
            if op == "AND":
                return int(l) & int(r)
            if op == "OR":
                return int(l) | int(r)
            return int(l) ^ int(r)
        if op in ("=", "<>", "<", ">", "<=", ">="):
            if op == "=":
                return l == r
            if op == "<>":
                return l != r
            if op == "<":
                return l < r
            if op == ">":
                return l > r
            if op == "<=":
                return l <= r
            return l >= r

        is_real = isinstance(l, float) or isinstance(r, float)
        if op == "+":
            return l + r
        if op == "-":
            return l - r
        if op == "*":
            return l * r
        if op == "/":
            if r == 0:
                raise SimError("除以零", line)
            if is_real:
                return l / r
            # IEC 整数除法：向零截断，不是向下取整
            return int(l / r)
        if op == "MOD":
            if r == 0:
                raise SimError("MOD 除数为零", line)
            q = math.trunc(l / r)
            return l - q * r
        if op == "**":
            return l**r
        raise SimError(f"未知运算符 {op}", line)

    def _truthy(self, v: Any) -> bool:
        if isinstance(v, bool):
            return v
        if isinstance(v, (int, float)):
            return v != 0
        raise SimError(f"不能作为条件的值 {v!r}")

    # ---- 函数调用 ----
    def _call(self, node: Node) -> Any:
        name = (node.tok.value if node.tok else "").upper()
        if name in ("TIME", "LTIME"):
            if self.clock_ms is None:
                raise SimError("Clock read requires an explicit scan_interval_ms schedule", node.line)
            return self.clock_ms % (2**32) if name == "TIME" else self.clock_ms * 1000000
        if name in ("TO_TIME", "TO_LTIME"):
            value = int(self.eval(node.args[0]))
            return _duration_cast(value, node.args[0].typ, name.removeprefix("TO_"))
        edge_type=self.types.get(name.lower(), "").upper()
        if edge_type in ("R_TRIG","F_TRIG"):
            edge=self.mem[name.lower()].values;outputs=[]
            for index,arg in enumerate(node.args):
                pin=node.call_names[index] or "CLK:="
                if pin=="Q=>":outputs.append(arg)
                elif pin=="CLK:=":edge["CLK"]=bool(self.eval(arg))
                else:raise SimError("Invalid edge detector argument",node.line)
            signal=bool(edge["CLK"])
            edge["Q"]=(signal and not edge["_M"]) if edge_type=="R_TRIG" else (not signal and not edge["_M"])
            edge["_M"]=signal if edge_type=="R_TRIG" else not signal
            for dest in outputs:self.assign(dest,edge["Q"],node.line)
            return None
        if self.types.get(name.lower(), "").upper() == "TON":
            if self.clock_ms is None:
                raise SimError("TON requires a test schedule with scan_interval_ms", node.line)
            timer = self.mem[name.lower()].values
            outputs = []
            for index, arg in enumerate(node.args):
                pin = node.call_names[index] or ("IN:=", "PT:=")[index]
                if pin.endswith("=>"):
                    outputs.append((pin[:-2], arg))
                else:
                    value = self.eval(arg)
                    timer[pin[:-2]] = _duration_cast(value, arg.typ, "TIME") if pin == "PT:=" else value
            if not timer["IN"]:
                timer.update(_start_ms=None, ET=0, Q=False)
            else:
                if timer["_start_ms"] is None:
                    timer["_start_ms"] = self.clock_ms
                elapsed = self.clock_ms - timer["_start_ms"]
                timer.update(ET=min(elapsed, timer["PT"]), Q=elapsed >= timer["PT"])
            for pin, dest in outputs:
                value = _duration_cast(timer[pin], "TIME", dest.typ) if pin == "ET" else timer[pin]
                self.assign(dest, value, node.line)
            return None

        # 类型转换 INT_TO_REAL / WORD_TO_BOOL ...
        # 但 STRING_TO_INT / STRING_TO_REAL 要走字符串分支（空串、非数字要返回 0
        # 而不是抛 ValueError），所以这里先把 STRING 源排除掉。
        if "_TO_" in name and not name.startswith("STRING_TO_"):
            src, dst = name.split("_TO_", 1)
            v = self.eval(node.args[0])
            if src in {"TIME", "LTIME"} and dst in {"TIME", "LTIME"}:
                return _duration_cast(int(v), src, dst)
            if dst in _REAL_TYPES:
                return float(v)
            if dst in _BOOL_TYPES:
                return bool(v)
            if dst in _INT_TYPES:
                return _wrap_int(int(v), dst)
            return v

        if name in ("ABS",):
            return abs(self.eval(node.args[0]))
        # ---- IEC 61131-3 字符串标准库 ----
        # 字符串解析题（如 IPv4 点分十进制）离不开这几个函数。
        if name == "LEN":
            return len(str(self.eval(node.args[0])))
        if name == "CONCAT":
            return "".join(str(self.eval(a)) for a in node.args)
        if name == "LEFT":
            s, n = str(self.eval(node.args[0])), int(self.eval(node.args[1]))
            return s[:n] if n > 0 else ""
        if name == "RIGHT":
            s, n = str(self.eval(node.args[0])), int(self.eval(node.args[1]))
            return s[-n:] if n > 0 else ""
        if name == "MID":
            s = str(self.eval(node.args[0]))
            n = int(self.eval(node.args[1]))
            p = int(self.eval(node.args[2])) if len(node.args) > 2 else 1
            if p < 1 or n <= 0:
                return ""
            return s[p - 1:p - 1 + n]
        if name == "FIND":
            s, sub = str(self.eval(node.args[0])), str(self.eval(node.args[1]))
            pos = s.find(sub)
            return pos + 1 if pos >= 0 else 0   # IEC：没找到返回 0，位置从 1 起
        if name == "DELETE":
            s = str(self.eval(node.args[0]))
            n = int(self.eval(node.args[1]))
            p = int(self.eval(node.args[2])) if len(node.args) > 2 else 1
            if p < 1 or n < 0:
                return s
            return s[:p - 1] + s[p - 1 + n:]
        if name == "INSERT":
            s1 = str(self.eval(node.args[0]))
            s2 = str(self.eval(node.args[1]))
            p = int(self.eval(node.args[2])) if len(node.args) > 2 else 1
            if p < 1:
                return s2 + s1
            return s1[:p - 1] + s2 + s1[p - 1:]
        if name == "REPLACE":
            s1 = str(self.eval(node.args[0]))
            s2 = str(self.eval(node.args[1]))
            n = int(self.eval(node.args[2]))
            p = int(self.eval(node.args[3])) if len(node.args) > 3 else 1
            if p < 1 or n < 0:
                return s1
            return s1[:p - 1] + s2 + s1[p - 1 + n:]
        if name == "TRIM":
            return str(self.eval(node.args[0])).strip()
        if name == "STRING_TO_INT":
            try:
                return int(float(str(self.eval(node.args[0])).strip() or "0"))
            except ValueError:
                return 0
        if name == "STRING_TO_REAL":
            try:
                return float(str(self.eval(node.args[0])).strip() or "0")
            except ValueError:
                return 0.0
        if name == "INT_TO_STRING":
            return str(int(self.eval(node.args[0])))
        if name == "REAL_TO_STRING":
            return str(float(self.eval(node.args[0])))
        if name == "MIN":
            return min(self.eval(a) for a in node.args)
        if name == "MAX":
            return max(self.eval(a) for a in node.args)
        if name == "LIMIT":
            lo, v, hi = (self.eval(a) for a in node.args)
            return max(lo, min(v, hi))
        if name == "SEL":
            g, a, b = (self.eval(x) for x in node.args)
            return a if self._truthy(g) else b
        if name == "MUX":
            k = int(self.eval(node.args[0]))
            if 0 <= k < len(node.args) - 1:
                return self.eval(node.args[k + 1])
            return 0
        if name == "SQRT":
            return math.sqrt(self.eval(node.args[0]))
        if name == "MOD":
            return self._binop("MOD", self.eval(node.args[0]), self.eval(node.args[1]), node.line)
        if name in ("SHL", "SHR", "ROL", "ROR"):
            v = int(self.eval(node.args[0]))
            n = int(self.eval(node.args[1]))
            if name == "SHL":
                return v << n
            if name == "SHR":
                return v >> n
            return v
        if name in ("LOWER_BOUND", "UPPER_BOUND"):
            # LOWER_BOUND(arr, dim)
            # 数组边界是**实例**属性：VARIANT 的容量在运行时才定，不能只看
            # 声明的类型串。所以先取值，拿不到 ArrayValue 再退回类型声明。
            if node.args:
                try:
                    arr = self._unwrap(self.eval(node.args[0]))
                except (SimError, SimulationTimeout):
                    arr = None
                if isinstance(arr, ArrayValue):
                    return arr.lo if name == "LOWER_BOUND" else arr.hi
                if node.args[0].kind == "name":
                    key = node.args[0].tok.value.lower()
                    dtype = self.types.get(key, "")
                    b = _array_bounds(dtype)
                    if b and b[0] is not None:
                        return b[0] if name == "LOWER_BOUND" else b[1]
            return 0

        # 调用本题内的另一个 POU（很少见），或未定义的函数
        if name.lower() in self.mem:
            return 0
        raise SimError(f"未定义的函数 {name}", node.line)


class _BreakLoop(Exception):
    """内部信号：EXIT 跳出循环。"""


# --------------------------------------------------------------------------
# 对外：跑一组测试用例
# --------------------------------------------------------------------------


def simulate(
    src: str,
    inputs: list[str],
    outputs: list[str],
    vectors: list[dict[str, Any]],
    *,
    const_inputs: dict[str, Any] | None = None,
    keep_state_between_vectors: bool = False,
    restart_each: bool = False,
) -> SimOutcome:
    """跑仿真。

    ``vectors`` 是逐周期的输入字典；
    ``const_inputs`` 是全程保持的常量输入；
    每个向量里的 ``_expect`` 是**该周期结束后**要断言的输出。

    ``restart_each=True`` 时每个向量都用**全新实例**跑（单周期用例模式），
    这样"保持上一周期输出"这类断言必须靠用例自带的初值来表达，而不是靠
    上一条用例的副作用——后者会让用例之间产生隐含耦合，结果不可复现。
    """
    res = typecheck(compile_st(src))
    if res.pou is None:
        return SimOutcome(ok=False, message="没有可仿真的 POU：" +
                          "; ".join(str(d) for d in res.diags[:3]))
    errors = [d for d in res.diags if d.level == "error"]
    if errors:
        return SimOutcome(
            ok=False,
            message="静态检查未通过，未进入仿真：" + "; ".join(str(d) for d in errors[:3]),
        )

    const = const_inputs or {}
    const_keys = {k.lower() for k in const}
    # VAR_IN_OUT 形参：只在其首次出现的周期用向量值初始化实参，之后视为程序写回的目标。
    _inout_names: set[str] = set()
    if res.pou is not None:
        for _d in res.pou.decls:
            if str(getattr(_d, "section", "")).upper().startswith("VAR_IN_OUT"):
                _inout_names.add(_d.name.lower())
    _seeded: set[str] = set()
    trace: list[dict[str, Any]] = []
    interp = Interpreter(res.pou, res.structs)

    try:
        for cycle, vec in enumerate(vectors, start=1):
            # IEC 标识符大小写不敏感，用例里写 'ipText' 或 'iptext' 都得认。
            vec_lower = {str(k).lower(): v for k, v in vec.items()}
            if restart_each:
                # 单周期用例必须能表达"实例上电前的存储状态"（保持型变量、
                # 输出初值）。所以每次重启后先创建实例，再把 _init 叠加上去；
                # 顺序反了就会把初值冲掉，注释里的承诺也就成了空话。
                interp = Interpreter(res.pou, res.structs)
                for k, v in const.items():
                    interp.set_var(k, v)
                for k, v in (vec.get("_init") or {}).items():
                    interp.set_var(k, v)
            for k, v in const.items():
                interp.set_var(k, v)
            for k in inputs:
                # 本周期向量里没写的输入：
                #   * 在 const_inputs 里 -> 保持常量，**不能覆盖**（否则数值输入
                #     会被当成 BOOL 清成 FALSE，这是最容易踩的坑）；
                #   * 否则按 PLC 默认值处理——BOOL 为 FALSE，其余保持原值。
                #
                # 关键：用例向量的键可能是 'ipText' 也可能是 'iptext'，IEC 标识符
                # 大小写不敏感。直接写 `k.lower() in vec` 会让 'ipText' 这类驼峰
                # 键判不中，输入被静默丢弃——表现为"所有字符串输入都是空串"，
                # 且不报任何错。所以这里按小写建一次索引来查。
                nk = k.lower()
                # VAR_IN_OUT 是双向的：
                #   * 向量里给了值 -> 当作本周期的实参输入（如入队数据 item）；
                #   * 向量里没给值 -> 保留程序上一周期的写回结果（如出队结果的
                #     item），不能拿声明时的初始值去冲掉它。
                # 早期实现"IN_OUT 只在首周期赋值"是错的：那样第 2 周期入队
                # 就永远拿不到新的 item，表现为"缓冲区里全是 0"。
                if nk in _inout_names:
                    if nk in vec_lower:
                        interp.set_var(k, vec_lower[nk])
                    continue
                if nk in vec_lower:
                    interp.set_var(k, vec_lower[nk])
                elif nk in const_keys:
                    continue
                elif interp.types.get(nk, "").upper() == "BOOL":
                    interp.set_var(k, False)
            for _ in range(int(vec.get("_cycles", 1) or 1)):
                interp.scan(vec.get("_scan_interval_ms"))
            snap = {o: Interpreter._unwrap(interp.get_var(o)) for o in outputs if o.lower() in interp.mem}
            trace.append({"cycle": cycle, "outputs": snap})

            for out_name, expect in vec.get("_expect", {}).items():
                actual = interp.get_var(out_name)
                # VARIANT 输出要按"壳里的值"比较：题面断言写的是 ``item: 10``，
                # 不能因为多了一层泛型包装就判成不等。
                cmp_actual = Interpreter._unwrap(actual)
                if not _match(cmp_actual, expect):
                    return SimOutcome(
                        ok=False,
                        cycles_run=cycle,
                        failure_cycle=cycle,
                        failure_var=out_name,
                        expected=expect,
                        actual=actual,
                        message=f"第{cycle}周期 {out_name} 期望 {expect!r}，实际 {actual!r}",
                        trace=trace,
                    )
        return SimOutcome(ok=True, cycles_run=len(vectors), trace=trace)
    except SimulationTimeout as e:
        return SimOutcome(ok=False, cycles_run=len(trace), message=f"仿真超时：{e}", trace=trace)
    except SimError as e:
        return SimOutcome(
            ok=False,
            cycles_run=len(trace),
            failure_cycle=len(trace) + 1,
            message=f"运行期错误（第{e.line}行）：{e}",
            trace=trace,
        )


def _plain_value(v: Any) -> Any:
    """把运行期值转成可比较的普通 Python 值。

    ``StructValue``/``ArrayValue``/``VariantValue`` 都是 dataclass 包装，直接与
    用例里的 ``dict``/``list`` 做 ``==`` 会走 ``__eq__`` 返回 NotImplemented，
    结果是"期望值与实际值完全一致也判错"。这里只做**比较层的解包**，不改仿真
    语义：结构体→``{字段: 值}``，数组→``[元素]``（按 lo 起的自然顺序），
    VARIANT→内层值（递归）。
    """
    while isinstance(v, VariantValue):
        v = v.value
    if isinstance(v, StructValue):
        return {k: _plain_value(x) for k, x in v.values.items()}
    if isinstance(v, ArrayValue):
        return [_plain_value(x) for x in v.items]
    return v


def _match(actual: Any, expected: Any) -> bool:
    """浮点按 1e-6 相对误差比较；结构体按字段子集、数组按整表比较。

    * 结构体断言写 ``{"字段": 值, ...}``：**允许只写关心的字段**（子集语义），
      没写的字段不参与判定——与"输出断言只写关心的输出"是同一口径；
    * 数组断言写 ``[...]``：长度必须一致，逐元素比较。若契约只规定有效前缀，
      则写 ``{"$prefix": [...]}``：从数组声明下界开始比较，忽略剩余槽位。
    """
    actual = _plain_value(actual)
    expected = _plain_value(expected)
    if isinstance(expected, dict):
        if isinstance(actual, list) and set(expected) == {"$prefix"}:
            prefix = expected["$prefix"]
            return (isinstance(prefix, list) and len(prefix) <= len(actual)
                    and all(_match(a, e) for a, e in zip(actual, prefix)))
        if not isinstance(actual, dict):
            return False
        return all(k in actual and _match(actual[k], v) for k, v in expected.items())
    if isinstance(expected, (list, tuple)):
        if not isinstance(actual, list) or len(actual) != len(expected):
            return False
        return all(_match(a, e) for a, e in zip(actual, expected))
    if isinstance(expected, float) or isinstance(actual, float):
        try:
            a, b = float(actual), float(expected)
        except (TypeError, ValueError):
            return False
        return abs(a - b) <= 1e-6 * max(1.0, abs(b))
    return actual == expected

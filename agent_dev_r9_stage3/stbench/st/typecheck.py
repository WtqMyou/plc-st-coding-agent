"""类型检查：在语法树之上做名称解析与类型推导。

它回答三类问题，全部是真实 CODESYS 编译会拒绝的错误：

1. **名称是否存在**——拼错 ``kikc``、漏声明、用错字段名；
2. **类型是否匹配**——``IF intVar THEN``、把 BOOL 赋给 REAL、比较两边不可比；
3. **只读是否被写**——给 ``VAR_INPUT`` 赋值（这是 ST 里最常见的语义错误，
   而且它不会让程序崩溃，只会让结果永远不对，最值得静态拦住）。

另外还检查"调用未声明的结构体字段"和"数组常量下标越界"。

局限（报告里必须写清）
----------------------
不做数据流分析，因此抓不到：算法逻辑错、状态机漏分支、整数溢出、
除零、以及任何"能编译但算错"的问题——后者交给测试用例与 LTL 规约。
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from .frontend import (
    ELEMENTARY,
    STD_FUNCS,
    CompileResult,
    Decl,
    Diag,
    Node,
    POU,
    StructType,
    compile_st,
)


def _cat(t: str | None) -> str:
    """把类型名归到一个粗类别：bool / int / real / time / string / struct / any。"""
    if not t:
        return "any"
    up = t.upper()
    if up in ELEMENTARY:
        return ELEMENTARY[up]
    if up.startswith("ARRAY"):
        return "array"
    return "struct"


def _num_width(t: str) -> int:
    """整数位宽，用于宽松的兼容判断。"""
    up = t.upper()
    return {
        "SINT": 8, "INT": 16, "DINT": 32, "LINT": 64,
        "USINT": 8, "UINT": 16, "UDINT": 32, "ULINT": 64,
        "BYTE": 8, "WORD": 16, "DWORD": 32, "LWORD": 64,
    }.get(up, 32)


@dataclass
class Scope:
    """一个 POU 的可见符号表。"""

    pou: POU
    structs: dict[str, StructType]
    # name -> (data_type, section)
    vars: dict[str, tuple[str, str]] = field(default_factory=dict)
    errors: list[Diag] = field(default_factory=list)

    def visible(self, name: str) -> tuple[str, str] | None:
        """大小写不敏感查找（IEC 61131-3 标识符不区分大小写）。"""
        if name in self.vars:
            return self.vars[name]
        low = name.lower()
        for k, v in self.vars.items():
            if k.lower() == low:
                return v
        return None


class Checker:
    def __init__(self, res: CompileResult):
        self.res = res
        self.structs = res.structs
        # 从 POU 声明里自动补出结构体定义（题目接口里给过字段表时用）
        self.diags: list[Diag] = []
        self.scope: Scope | None = None
        self.enums = {k.lower(): v for k, v in self.structs.items() if hasattr(v, 'members')}

    # ---- 诊断 ----
    def err(self, line: int, code: str, msg: str) -> None:
        self.diags.append(Diag("error", line, code, msg))

    def warn(self, line: int, code: str, msg: str) -> None:
        self.diags.append(Diag("warning", line, code, msg))

    # ---- 主流程 ----
    def run(self) -> list[Diag]:
        pou = self.res.pou
        if pou is None:
            self.err(1, "E_NO_POU", "没有找到 FUNCTION_BLOCK / FUNCTION / PROGRAM 定义")
            return self.diags

        self.scope = Scope(pou, self.structs)
        for d in pou.decls:
            if d.name in self.scope.vars:
                self.err(d.line, "E_DUP_DECL", f"变量 {d.name!r} 重复声明")
            self.scope.vars[d.name] = (d.data_type, d.section)
            if d.init is not None:
                self.infer(d.init, writable=False, context=f"{d.name} 的初值")
                if d.data_type.lower() in self.enums:
                    self.check_assignable(d.data_type, d.init, d.line)

        for st in pou.body:
            self.check_stmt(st)

        # 输出变量从未被赋值，通常意味着漏了逻辑
        written: set[str] = set()
        self._collect_written(pou.body, written)
        for d in pou.decls:
            if d.section == "VAR_OUTPUT" and d.name not in written:
                self.warn(d.line, "W_UNWRITTEN_OUT",
                          f"输出变量 {d.name!r} 从未被赋值")
        return self.diags

    def _collect_written(self, stmts: list[Node], out: set[str]) -> None:
        for st in stmts:
            if st.kind == "assign" and st.args:
                out.add(self._root_name(st.args[0]))
            self._collect_written(st.stmts, out)
            for _, body in st.elifs:
                self._collect_written(body, out)
            self._collect_written(st.else_body, out)

    @staticmethod
    def _root_name(node: Node) -> str:
        while node.kind in ("member", "index") and node.args:
            node = node.args[0]
        return node.tok.value if node.tok else ""

    # ---- 语句 ----
    def check_stmt(self, st: Node) -> None:
        k = st.kind
        if k == "assign":
            target, value = st.args
            ttype = self.infer(target, writable=True)
            self.infer(value, writable=False)
            self.check_assignable(ttype, value, st.line)
        elif k == "if":
            self.check_condition(st.args[0])
            for s in st.stmts:
                self.check_stmt(s)
            for cond, body in st.elifs:
                self.check_condition(cond)
                for s in body:
                    self.check_stmt(s)
            for s in st.else_body:
                self.check_stmt(s)
        elif k == "case":
            self.infer(st.args[0], writable=False)
            for label, body in st.elifs:
                for lb in label.args:
                    self.infer(lb, writable=False)
                for s in body:
                    self.check_stmt(s)
            for s in st.else_body:
                self.check_stmt(s)
        elif k == "for":
            loop = st.tok
            if loop is None:
                self.err(st.line, "E_FOR", "FOR 循环缺少循环变量")
                return
            var = Node("name", st.line, tok=loop)
            self.infer(var, writable=True)
            for a in st.args:
                self.infer(a, writable=False)
            for s in st.stmts:
                self.check_stmt(s)
        elif k == "while":
            self.check_condition(st.args[0])
            for s in st.stmts:
                self.check_stmt(s)
        elif k == "repeat":
            for s in st.stmts:
                self.check_stmt(s)
            self.check_condition(st.args[0])
        elif k in ("return", "exit", "nop"):
            return
        elif k == "call":
            self.infer(st, writable=False)
        elif k == "exprstmt":
            self.infer(st.args[0], writable=False)
        else:
            for a in st.args:
                self.infer(a, writable=False)
            for s in st.stmts:
                self.check_stmt(s)

    def check_condition(self, node: Node) -> None:
        t = self.infer(node, writable=False)
        if t is None:
            return
        if _cat(t) not in ("bool", "any"):
            self.err(node.line, "E_COND_TYPE",
                     f"条件表达式类型是 {t}，应为 BOOL")

    def check_assignable(self, target_type: str | None, value: Node, line: int) -> None:
        vt = value.typ
        if target_type is None or vt is None:
            return
        if target_type.lower() in self.enums or vt.lower() in self.enums:
            if target_type.lower() == vt.lower():
                return
            target_enum = self.enums.get(target_type.lower())
            source_enum = self.enums.get(vt.lower())
            literal = self._const_value(value)
            if target_enum and literal is not None and literal in target_enum.members.values():
                return
            if ((target_enum and target_enum.strict) or (source_enum and source_enum.strict) or
                    (target_enum is None and _cat(target_type) != 'int') or
                    (source_enum is None and _cat(vt) != 'int')):
                self.err(line, 'E_ENUM_TYPE', f'枚举类型不兼容：{vt} 不能赋给 {target_type}')
            return
        tc, vc = _cat(target_type), _cat(vt)
        if tc == "any" or vc == "any":
            return
        if tc == vc:
            # 整数降位赋值只提醒不报错（CODESYS 允许但可能截断）
            if tc == "int" and _num_width(vt) > _num_width(target_type):
                self.warn(line, "W_NARROW", f"{vt} 赋给 {target_type} 可能截断")
            return
        # real <- int 允许；int <- real 视为错误（隐式丢精度，真实编译器多要求转换）
        if tc == "real" and vc == "int":
            return
        if tc == "array" or vc == "array":
            if target_type.split("OF")[-1].strip() == vt.split("OF")[-1].strip():
                return
        self.err(line, "E_TYPE_MISMATCH",
                 f"类型不匹配：{vt} 不能赋给 {target_type}")

    # ---- 表达式：返回推导出的类型名 ----
    def infer(self, node: Node, *, writable: bool, context: str = "") -> str | None:
        k = node.kind

        if k in ("num", "str", "bool"):
            return node.typ

        if k == "name":
            name = node.tok.value if node.tok else ""
            found = self.scope.visible(name) if self.scope else None
            if found is None:
                matches = [e for e in self.enums.values() if not e.qualified_only and any(m.lower() == name.lower() for m in e.members)]
                if matches:
                    if len(matches) != 1:
                        self.err(node.line, 'E_ENUM_AMBIGUOUS', f'枚举成员 {name!r} 需要类型限定')
                        return None
                    if writable:
                        self.err(node.line, 'E_WRITE_CONSTANT', '枚举成员是只读常量')
                    node.typ = matches[0].name
                    return node.typ
                if name.upper() in STD_FUNCS:
                    node.typ = "FUNC"
                    return "FUNC"
                self.err(node.line, "E_UNDECLARED",
                         f"使用了未声明的标识符 {name!r}" + (f"（{context}）" if context else ""))
                return None
            dtype, section = found
            if section == "VAR_INPUT":
                if writable:
                    self.err(node.line, "E_WRITE_INPUT",
                             f"不能给输入变量 {name!r} 赋值（VAR_INPUT 对 FB 内部只读）")
            node.typ = dtype
            return dtype

        if k == "member":
            base = node.args[0]
            enum = self.enums.get(base.tok.value.lower()) if base.kind == 'name' and base.tok else None
            if enum is not None and not self.scope.visible(base.tok.value):
                if not any(m.lower() == node.tok.value.lower() for m in enum.members):
                    self.err(node.line, 'E_ENUM_MEMBER', '未声明的枚举成员')
                    return None
                if writable:
                    self.err(node.line, 'E_WRITE_CONSTANT', '枚举成员是只读常量')
                node.typ = enum.name
                return node.typ
            btype = self.infer(base, writable=writable, context=context)
            if btype is None:
                return None
            # 剥掉 ARRAY 外壳，取元素/标称类型
            st_name = btype
            if " OF " in st_name.upper():
                st_name = st_name.split(" OF ", 1)[1].strip()
            st = self.structs.get(st_name)
            field_name = node.tok.value if node.tok else ""
            if st is not None:
                ftype = st.fields.get(field_name)
                if ftype is None:
                    # 大小写不敏感兜底
                    for fn, ft in st.fields.items():
                        if fn.lower() == field_name.lower():
                            ftype = ft
                            break
                if ftype is None:
                    self.err(node.line, "E_NO_FIELD",
                             f"结构体 {st_name} 没有字段 {field_name!r}")
                    return None
                node.typ = ftype
                return ftype
            # 未知结构体：只做名称拼写提示，不定类型
            node.typ = None
            return None

        if k == "index":
            base = node.args[0]
            btype = self.infer(base, writable=writable, context=context)
            for idx in node.args[1:]:
                self.infer(idx, writable=False)
            if btype is None:
                return None
            # IEC 61131-3：S[1] 是单字符 STRING，S[1..3] 是子串。之前只认 ARRAY，
            # 把字符串下标判成 E_NOT_ARRAY，导致所有字符串解析题都写不出来。
            if _cat(btype) == "string":
                node.typ = "STRING"
                return "STRING"
            # VARIANT 是运行时才定型的泛型引用：题面把它当"任意元素类型的数组"用，
            # 编译期只能放过（元素类型记 ANY），越界由仿真器的 ArrayValue 兜底。
            if btype.upper() == "VARIANT":
                node.typ = "ANY"
                return "ANY"
            if _cat(btype) != "array":
                self.err(node.line, "E_NOT_ARRAY", f"{self._root_name(base)!r} 不是数组，不能用下标")
                return None
            # 常量下标越界检查
            lo, hi = self._array_bounds(btype)
            if lo is not None and len(node.args) >= 2:
                lit = self._const_value(node.args[1])
                if lit is not None and not (lo <= lit <= hi):
                    self.err(node.line, "E_INDEX_RANGE",
                             f"常量下标 {lit} 超出数组范围 [{lo}..{hi}]")
            elem = btype.split(" OF ", 1)[1].strip() if " OF " in btype.upper() else "ANY"
            node.typ = elem
            return elem

        # CASE 标签里的 a..b 范围：两边都得能求值，类型应与选择器一致
        if k == "range":
            for a in node.args:
                self.infer(a, writable=False)
            node.typ = node.args[0].typ
            return node.typ

        if k == "call":
            callee = node.tok.value if node.tok else ""
            up = callee.upper()
            if up in STD_FUNCS:
                ret, nmin, nmax = STD_FUNCS[up]
                if not (nmin <= len(node.args) <= nmax):
                    self.err(node.line, "E_ARG_COUNT",
                             f"{up} 需要 {nmin}..{nmax} 个参数，实际 {len(node.args)}")
                for a in node.args:
                    self.infer(a, writable=False)
                node.typ = {"any": None, "int": "INT", "real": "REAL",
                            "bool": "BOOL"}.get(ret)
                return node.typ
            # 其他：可能是转换函数 INT_TO_REAL 或用户自定义函数
            if up.startswith(("_TO_",)) or "_TO_" in up:
                dst = up.split("_TO_")[-1]
                for a in node.args:
                    self.infer(a, writable=False)
                node.typ = dst
                return dst
            for a in node.args:
                self.infer(a, writable=False)
            found = self.scope.visible(callee) if self.scope else None
            if found:
                node.typ = found[0]
                return found[0]
            self.err(node.line, "E_UNKNOWN_FUNC", f"调用了未知函数/功能块 {callee!r}")
            return None

        if k == "unop":
            t = self.infer(node.args[0], writable=False)
            op = node.tok.value.upper() if node.tok else ""
            if t and t.lower() in self.enums and self.enums[t.lower()].strict:
                self.err(node.line, 'E_ENUM_ARITHMETIC', '枚举不支持算术或位操作')
            if op == "NOT":
                # IEC 61131-3：NOT 对 BOOL 是按位取反，对整数类操作数同样是按位补码。
                # 之前一律要求 BOOL，导致 "NOT: bitmask" 这种合法写法被拒。
                if t is not None and _cat(t) not in ("bool", "int", "any"):
                    self.err(node.line, "E_NOT_TYPE",
                             f"NOT 只能用于 BOOL 或整数类型，实际是 {t}")
                node.typ = "BOOL" if (t is None or _cat(t) == "bool") else t
                return node.typ
            node.typ = t
            return t

        if k == "binop":
            lt = self.infer(node.args[0], writable=False)
            rt = self.infer(node.args[1], writable=False)
            op = (node.tok.value if node.tok else "").upper()
            lc = _cat(lt) if lt is not None else "any"
            rc = _cat(rt) if rt is not None else "any"
            if (lt and lt.lower() in self.enums) or (rt and rt.lower() in self.enums):
                le = self.enums.get((lt or '').lower())
                re = self.enums.get((rt or '').lower())
                if (le and le.strict) or (re and re.strict):
                    if op not in ('=', '<>', '<', '>', '<=', '>=') or not lt or not rt or lt.lower() != rt.lower():
                        self.err(node.line, 'E_ENUM_TYPE', '严格枚举运算必须为同类型枚举之间的比较')
                    node.typ = 'BOOL' if op in ('=', '<>', '<', '>', '<=', '>=') else lt
                    return node.typ
                lt, rt = le.base_type if le else lt, re.base_type if re else rt
                lc, rc = _cat(lt), _cat(rt)
            if op in ("SHL", "SHR", "ROL", "ROR"):
                # 移位：左操作数可为整数类或 BOOL（按 0/1 处理），右操作数是位数
                node.typ = lt or "INT"
                if lc not in ("int", "bool", "any"):
                    self.err(node.line, "E_SHIFT_TYPE",
                             f"{op} 的左操作数类型是 {lt}，应为整数或 BOOL")
                if rc not in ("int", "any"):
                    self.err(node.line, "E_SHIFT_TYPE",
                             f"{op} 的移位量类型是 {rt}，应为整数")
                return node.typ
            if op in ("AND", "OR", "XOR"):
                # IEC 61131-3 里 AND/OR/XOR 是二义性的：BOOL 上做逻辑，整数上做按位。
                # 之前一律要求 BOOL，把 "mask AND pattern" 这种完全合法的位运算拒掉了。
                both_int = lc in ("int", "any") and rc in ("int", "any") \
                    and "bool" not in (lc, rc)
                if both_int:
                    node.typ = lt or rt or "INT"
                    return node.typ
                node.typ = "BOOL"
                for side, t in (("左", lt), ("右", rt)):
                    if t is not None and _cat(t) not in ("bool", "any"):
                        self.err(node.line, "E_LOGIC_TYPE",
                                 f"{op} 的{side}操作数类型是 {t}，应为 BOOL")
                return "BOOL"
            if op in ("=", "<>", "<", ">", "<=", ">="):
                node.typ = "BOOL"
                if lt is not None and rt is not None:
                    lc, rc = _cat(lt), _cat(rt)
                    if lc != rc and "any" not in (lc, rc) and {lc, rc} != {"int", "real"}:
                        self.err(node.line, "E_COMPARE_TYPE",
                                 f"比较的两边类型不可比：{lt} 与 {rt}")
                return "BOOL"
            # 算术运算
            if op == "&":
                node.typ = "STRING"
                return "STRING"
            if "real" in {_cat(lt), _cat(rt)}:
                node.typ = "REAL"
            else:
                node.typ = lt or rt or "INT"
            return node.typ

        return None

    @staticmethod
    def _const_value(node: Node) -> int | None:
        if node.kind == "num" and node.tok is not None:
            v = node.tok.num
            return int(v) if isinstance(v, (int, float)) else None
        if node.kind == "unop" and node.tok and node.tok.value == "-":
            inner = Checker._const_value(node.args[0])
            return -inner if inner is not None else None
        return None

    def _array_bounds(self, dtype: str) -> tuple[int | None, int | None]:
        """从 'ARRAY[1..5] OF X' 里取上下界；'ARRAY[*]' 返回 (None, None)。"""
        import re

        m = re.search(r"\[\s*(-?\d+)\s*\.\.\s*(-?\d+)\s*\]", dtype)
        if m:
            return int(m.group(1)), int(m.group(2))
        return None, None


def typecheck(res: CompileResult) -> CompileResult:
    """在解析结果上跑类型检查，把诊断合并进同一个 CompileResult。"""
    if res.pou is None:
        return res
    checker = Checker(res)
    res.diags.extend(checker.run())
    res.ok = not any(d.level == "error" for d in res.diags)
    return res


def check_st(src: str) -> CompileResult:
    """对外唯一入口：源码字符串 → 完整编译结果。

    ``ok=True`` 表示"通过静态检查"，不等价于真实编译器通过，
    报告里必须以"通过静态检查"表述。
    """
    return typecheck(compile_st(src))

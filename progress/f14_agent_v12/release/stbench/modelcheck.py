# -*- coding: utf-8 -*-
"""有界模型检查：把 ST 程序当状态机，穷举输入序列，用 LTL 规约判定。

## 为什么需要它（课件 S1_1 第 44-45 页）

课件把"正确"定义成

    P ⊨ φ  ⟺  对所有轨迹 π ∈ Traces(P)，π ⊨ φ

而课件第 45 页的对照表指出：

    技术上        检查的轨迹        能证明正确吗
    ----------    --------------    ------------
    编译器        0（只有语法/类型）  ❌
    测试          少数几条手写的     ❌
    模型检查      模型的全部轨迹     ✅（对模型而言）

我们原来的系统只做了前两行——所以"参考解 75/75 全过"这句话的真实含义是
"在 75 条人挑的轨迹上没问题"，而课件里那个 LLM 写的 FB_Fill 也过了 4 个测试，
**却还是自己开了阀门**。

本模块补上第三行。做法不是符号模型检查（那要建 BDD，工作量大且对 ST 不友好），
而是**有界穷举**：

    1. 输入只有有限种组合（n 个 BOOL 输入 => 2^n 种赋值）；
    2. 枚举长度为 L 的输入序列，每一拍用解释器求出下一状态；
    3. 状态完全相同的两条轨迹，其后续行为必然相同 —— **状态去重**
       就把指数爆炸砍成"可达状态数 × 输入数"，这正是显式模型检查的做法；
    4. 对每条走到的新轨迹跑 LTL，找到反例就停。

代价是必须给轨迹一个上界 L（所以叫"有界"）。因此结论分成两档：

    * **证伪可靠**：找到反例 => 程序确实错了（和长度无关）。
    * **证真只是近似**：「在 L 拍内没违反」不等于「永远不违反」。

这个区分必须如实写进论文，课件第 37 页专门强调了这一点
（"One week can refute 'always', but never prove it"）。
"""

from __future__ import annotations

import itertools
import re
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Iterable

from .ltl import LtlNode, Verdict, evaluate, explain, parse
from .st.frontend import compile_st
from .st.interp import Interpreter, SimError, SimulationTimeout
from .st.typecheck import typecheck

# 前沿去重保留的历史快照个数。2 = 够 `prev()` 回看 1 拍。
# 改小会漏反例（边沿性质判错），改大只会更慢，不会更对。
HISTORY = 2


# --------------------------------------------------------------------------
# 状态去重的键
# --------------------------------------------------------------------------


def _state_key(interp: Interpreter) -> tuple:
    """把程序的**存储变量**压成一个可哈希的键（课件第 24 页的 ``m``）。

    ⚠️ **绝不能把输入变量算进状态键**，这是最容易写错的地方：
    输入是转移的**参数** i，不是下一个状态 m′ 的一部分。如果连输入一起做键，
    那么"同一个 m、不同 i"会被当成不同状态，而"展开到某个深度后没有新键"
    也就变成了假的闭合——实测会把 FB_Fill 的状态图错判成只有 2 层，
    于是 R4 这种"先关后开"的迁移性质永远检查不到。

    同理，输出变量每拍由 λ 重算、不跨拍记忆，严格说也不该进键；
    但保留它们只会让键更细（少合并几个等价状态），不会导致漏检，故保留。
    """
    parts: list[Any] = []
    for name in sorted(interp.mem):
        section = str(interp.sections.get(name, "")).upper()
        if section.startswith("VAR_INPUT"):
            continue  # 输入不是状态
        parts.append(_freeze(interp.mem[name]))
    return tuple(parts)


def _freeze(v: Any) -> Any:
    """把值转成可哈希形式（数组/结构体/泛型壳都能进 tuple）。"""
    from .st.interp import ArrayValue, StructValue, VariantValue

    if isinstance(v, VariantValue):
        return ("V", v.tag, _freeze(v.value))
    if isinstance(v, ArrayValue):
        return ("A", v.lo, v.hi, tuple(_freeze(x) for x in v.items))
    if isinstance(v, StructValue):
        return ("S", v.type_name, tuple((k, _freeze(x)) for k, x in sorted(v.values.items())))
    if isinstance(v, (list, tuple)):
        return tuple(_freeze(x) for x in v)
    if isinstance(v, dict):
        # 结构体输入在输入域里是**普通 dict**（不是 StructValue），
        # 不递归冻结就会在记忆化的键上抛 "unhashable type: 'dict'"。
        return ("D", tuple((str(k), _freeze(x)) for k, x in sorted(v.items())))
    return v


# --------------------------------------------------------------------------
# 快照
# --------------------------------------------------------------------------


def snapshot(interp: Interpreter) -> dict[str, Any]:
    """当前扫描结束后的完整快照：输入 + 内存 + 输出。

    课件第 15 页：一个状态 σ 是所有变量的取值。这里保持同样的语义，
    但把变量名统一小写，方便 LTL 里的原子命题大小写不敏感地引用。
    """
    from .st.interp import VariantValue

    out: dict[str, Any] = {}
    for name, v in interp.mem.items():
        out[name.lower()] = Interpreter._unwrap(v) if isinstance(v, VariantValue) else v
    return out


# --------------------------------------------------------------------------
# 输入空间
# --------------------------------------------------------------------------


@dataclass
class InputSpace:
    """受控输入的范围与取值集合。

    ``domains`` 把每个输入名字映射到它允许取的那些值。例如

        {"start": [False, True],
         "lsh":   [False, True],
         "level": [0, 5, 10, 15]}

    BOOL 输入默认就是 ``[False, True]``；数值输入**必须显式给**取值，
    否则穷举空间无穷大——这也是一种建模上的诚实：我们只检查我们建模了的值。
    """

    domains: dict[str, list[Any]] = field(default_factory=dict)
    fixed_inputs: tuple[str, ...] = ()

    @classmethod
    def from_bool_inputs(cls, names: Iterable[str]) -> "InputSpace":
        return cls({n: [False, True] for n in names})

    def combos(self) -> list[dict[str, Any]]:
        return list(self.iter_combos())

    def iter_combos(self):
        names = list(self.domains)
        if not names:
            yield {}
            return
        for vals in itertools.product(*(self.domains[n] for n in names)):
            yield dict(zip(names, vals))

    def size(self) -> int:
        total = 1
        for vals in self.domains.values():
            total *= max(len(vals), 1)
        return total

    def validate(self, names: set[str]) -> list[str]:
        """检查域里的名字是不是程序真有的输入。

        **这是必须的一步**：域写错名字时 set_var 会抛 SimError，如果像早期实现
        那样 try/except 吞掉，整张状态图会一个状态都展不出来，然后所有规约都
        "通过（有界）"—— 这是最危险的假绿，比报错糟糕得多。
        """
        domain_names={n.lower() for n in self.domains}
        return ([n for n in self.domains if n.lower() not in names] +
                [n for n in self.fixed_inputs if n.lower() not in domain_names or n.lower() not in names])


# --------------------------------------------------------------------------
# 检查结果
# --------------------------------------------------------------------------


@dataclass
class SpecResult:
    """单条规约的检查结论。"""

    spec_id: str
    formula: str
    holds: bool
    # holds=False 且 contradicting=True 说明**找到了具体反例**（结论可靠）
    contradicting: bool = False
    counterexample: list[dict[str, Any]] = field(default_factory=list)
    ce_at: int | None = None
    explanation: str = ""
    # holds=True 但 bounded=True：只是"在界内没违反"，不是证明
    bounded: bool = True
    inconclusive: bool = False
    reason: str = ""

    def status_text(self) -> str:
        if self.contradicting:
            return "违反"
        if self.inconclusive:
            return "界内无法判定"
        if self.holds:
            return "通过（有界）" if self.bounded else "通过"
        return "未通过"


@dataclass
class CheckReport:
    program: str
    specs: list[SpecResult] = field(default_factory=list)
    # 探索统计——论文里画"状态空间规模"要用
    states_explored: int = 0
    traces_explored: int = 0
    max_depth: int = 0
    input_space_size: int = 0
    error: str = ""
    # True 表示撞到了 max_traces / max_seconds：结论仍成立，但"检查到哪"被打断了，
    # 报告里必须写"预算内未发现违反"而不是"已验证"。
    truncated: bool = False
    fixed_input_domains: dict[str, list[Any]] = field(default_factory=dict)
    algorithm: str = ""
    stop_reason: str = ""
    completed_depth: int = 0
    current_depth: int = 0
    elapsed_seconds: float = 0.
    edges_checked: int = 0
    frontier_states: int = 0
    product_states: int = 0

    @property
    def all_hold(self) -> bool:
        return not self.error and not self.truncated and bool(self.specs) and all(s.holds and not s.inconclusive for s in self.specs)

    @property
    def contradictions(self) -> list[SpecResult]:
        return [s for s in self.specs if s.contradicting]

    def to_dict(self) -> dict[str, Any]:
        return {
            "program": self.program,
            **{name: getattr(self, name) for name in ("algorithm", "stop_reason", "completed_depth",
                "current_depth", "elapsed_seconds", "edges_checked", "frontier_states", "product_states")},
            "states_explored": self.states_explored,
            "traces_explored": self.traces_explored,
            "max_depth": self.max_depth,
            "input_space_size": self.input_space_size,
            "all_hold": self.all_hold,
            "error": self.error,
            "truncated": self.truncated,
            "fixed_input_domains": self.fixed_input_domains,
            "specs": [
                {
                    "id": s.spec_id,
                    "formula": s.formula,
                    "status": s.status_text(),
                    "holds": s.holds,
                    "contradicting": s.contradicting,
                    "bounded": s.bounded,
                    "inconclusive": s.inconclusive,
                    "counterexample_at": s.ce_at,
                    "reason": s.reason,
                }
                for s in self.specs
            ],
        }


# --------------------------------------------------------------------------
# 主入口
# --------------------------------------------------------------------------


def _st_literal(v: Any) -> str:
    """把 Python 值写成 ST 字面量，供 prev(...) 展开时回填进公式。"""
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, float):
        # 必须带小数点，否则会被 ST 当 INT，参与除法时语义就变了
        return repr(v)
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        return "'" + v.replace("'", "''") + "'"
    return "FALSE"


_PREV_RE = re.compile(r"\bprev\s*\(", re.IGNORECASE)


def _expand_prev(text: str, prev_snap: dict[str, Any] | None, eval_on) -> str:
    """把原子命题里的 ``prev(x)`` 换成上一拍的实际取值。

    为什么必须支持它：``G(!enable -> X(avgOut = prev(avgOut)))`` 这类"保持"性质
    是 PLC 规约里最高频的写法（比 ``X`` 版的 ``G(a -> X a)`` 更直观），
    LTL 本身没有跨时间比较，纯理论要靠辅助变量，而这里用求值期替换达到同样效果。

    首拍的"上一拍"是**声明初值**（由 modelcheck 以 init_snapshot 传入），
    也就是 PLC 上电瞬间存储区里的值。这样 ``G(guard -> x = prev(x))`` 这种
    "本拍没改变状态"的性质在第 1 拍才是可判定的；把 prev 取成硬编码 FALSE
    会让 ``count = prev(count)`` 退化成 ``count = 0``，在 count≠0 时误判。
    只有调用方没有提供初值时，才退化为 FALSE。
    """
    out = text
    guard = 0
    while True:
        guard += 1
        if guard > 32:  # 防御：正常情况下每轮都消掉一个 prev
            return out
        m = _PREV_RE.search(out)
        if not m:
            return out
        i = m.end()  # '(' 之后
        depth = 1
        j = i
        while j < len(out) and depth:
            if out[j] == "(":
                depth += 1
            elif out[j] == ")":
                depth -= 1
            j += 1
        if depth:
            raise ValueError(f"prev( 括号不配对：{text!r}")
        inner = out[i : j - 1]
        if prev_snap is None:
            val = "FALSE"
        else:
            val = _st_literal(eval_on(inner, prev_snap))
        out = out[: m.start()] + val + out[j:]


def _atom_evaluator(interp_types: dict[str, str], structs: dict[str, Any]) -> Callable[..., bool]:
    """把 LTL 原子命题当 ST 布尔表达式求值。

    做法：借解释器自己的表达式求值器。给一个临时 Interpreter，把快照灌进
    ``mem``，再调 ``eval``——这样 ``count >= 3``、``NOT valve``、
    ``buffer[1] = 5`` 这类写法全部自动支持，不用在 LTL 里再实现一遍表达式文法。
    """
    from .st.frontend import POU, Parser, tokenize

    cache = {}
    probe = Interpreter(POU("FUNCTION_BLOCK", "__ltl_snapshot", 0), structs)
    probe.types = interp_types
    probe.MAX_STEPS_PER_CYCLE = 10_000

    def eval_st(text, snap):
        if text not in cache:
            tokens, errors = tokenize(text)
            if errors or not tokens:
                raise ValueError(f"Invalid LTL atom: {text!r}")
            cache[text] = Parser(tokens).parse_expression()
        probe.mem = dict(snap)
        probe.steps = 0
        probe.depth = 0
        return probe.eval(cache[text])

    def ev_truthy(atom, snap, prev_snap=None):
        expanded = _expand_prev(atom, prev_snap, eval_st)
        return probe._truthy(eval_st(expanded, snap))

    ev_truthy._accepts_prev = True  # type: ignore[attr-defined]
    return ev_truthy


def check(
    src: str,
    specs: list[tuple[str, str]] | dict[str, str],
    input_space: InputSpace,
    *,
    max_depth: int = 12,
    max_traces: int = 20000,
    max_seconds: float | None = 60.0,
    program_name: str = "program",
    observer_name: str | None = None,
    observable_names: set[str] | None = None,
) -> CheckReport:
    """对有界轨迹集合做模型检查。

    ``specs`` 可以是 ``[(id, formula), …]`` 或 ``{id: formula}``。

    检查流程：
      1. 编译并静态检查（第一、二层：语法 + 类型）；
      2. 从初始状态出发，按输入空间广度优先展开状态图；
      3. 对每条**尚未检查过的轨迹前缀**跑 LTL，一旦违反就记下反例；
      4. 状态去重后，同一状态不重复展开。
    """
    started = time.monotonic()
    deadline = started + max_seconds if max_seconds else None
    if max_depth < 1 or max_traces < 1:
        raise ValueError("model-check depth and trace budget must be positive")
    if isinstance(specs, dict):
        specs = list(specs.items())

    rep = CheckReport(program=program_name, input_space_size=input_space.size())

    # ---- 第 1 层：编译 + 静态检查 ----
    res = typecheck(compile_st(src))
    errs = [d for d in res.diags if d.level == "error"]
    if errs or res.pou is None:
        rep.error = "静态检查未通过：" + "; ".join(str(d) for d in errs[:3])
        return rep

    from .spec_observers import observer_for, PREFIX
    observer = observer_for(observer_name)
    if observer and any(d.name.lower().startswith(PREFIX) for d in res.pou.decls):
        rep.error = 'Unsupported modeling: candidate declares reserved verification observer names'
        return rep
    def observed(snap, previous=None, initial=False):
        return snap | observer(snap, previous, initial) if observer else snap
    observer_names = set(observer({}, None, True)) if observer else set()
    # ---- 解析规约（解析失败说明数据集有缺陷，要显式报出来）----
    parsed: list[tuple[str, str, LtlNode]] = []
    for sid, text in specs:
        try:
            if observable_names is not None:
                from .spec_policy import formula_names
                missing = formula_names(text) - {n.lower() for n in observable_names} - observer_names
                if missing:
                    rep.specs.append(SpecResult(spec_id=sid, formula=text, holds=False,
                        inconclusive=True, reason='Unsupported binding: private names ' + ', '.join(sorted(missing))))
                    continue
            parsed.append((sid, text, parse(text)))
        except ValueError as e:
            rep.specs.append(
                SpecResult(
                    spec_id=sid,
                    formula=text,
                    holds=False,
                    inconclusive=True,
                    reason=f"LTL 解析失败（这是数据集缺陷，不是程序的问题）：{e}",
                )
            )

    from .product_search import explore
    return explore(rep, res, parsed, input_space, observer, observer_names, max_depth, max_traces,
                   deadline, started)
    
    
def _replay(res, trace: list[tuple[dict, dict]], combo: dict[str, Any]) -> Interpreter | None:
    """从初始状态开始重放已有轨迹，再把本拍的输入灌进去。

    重放而不是深拷贝：解释器内部有数组/结构体引用，手写深拷贝极易漏，
    而重放的开销（拍数很短）完全可以接受，且**语义上等价**。
    """
    it = Interpreter(res.pou, res.structs)
    for inp, _snap in trace:
        for name, val in inp.items():
            try:
                it.set_var(name, val)
            except SimError:
                return None
        try:
            it.scan()
        except (SimError, SimulationTimeout):
            return None
    for name, val in combo.items():
        try:
            it.set_var(name, val)
        except SimError:
            return None
    return it


def _trace_key(trace: list[tuple[dict, dict]]) -> tuple:
    """轨迹去重键：只看末端状态。

    理由和状态去重一样——同末态的两条轨迹，后续可达行为相同，
    而这些规约都是"从第 1 拍开始看整条轨迹"，所以判定结果一致。
    """
    if not trace:
        return ()
    # 注意 _freeze 对普通 dict 不递归（只有 StructValue 才走 S 分支），
    # 这里必须按 (键, 冻结值) 的元组来，否则整条轨迹的键是不可哈希的 dict。
    return tuple((k, _freeze(v)) for k, v in sorted(trace[-1][1].items()))

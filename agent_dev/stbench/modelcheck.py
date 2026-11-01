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

    @property
    def all_hold(self) -> bool:
        return not self.error and not self.truncated and bool(self.specs) and all(s.holds and not s.inconclusive for s in self.specs)

    @property
    def contradictions(self) -> list[SpecResult]:
        return [s for s in self.specs if s.contradicting]

    def to_dict(self) -> dict[str, Any]:
        return {
            "program": self.program,
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
    from .st.frontend import Diag, Parser, tokenize

    cache: dict[str, Any] = {}

    def _parse_atom(text: str):
        """把原子命题当 ST 表达式解析（复用同一个 Parser，不另写文法）。"""
        toks, _lex = tokenize(text)
        if not toks:
            raise ValueError(f"原子命题为空：{text!r}")
        pr = Parser(toks)
        node = pr.parse_expression()
        # parse_expression 是 Parser 的方法而非独立函数，包一层便于缓存
        return node

    def ev(atom: str, snap: dict[str, Any], prev_snap: dict[str, Any] | None = None) -> bool:
        # 先把 prev(...) 就地展开成"上一拍那个变量的字面值"。
        # 这是课件第 38 页那句注释的等价实现：
        #   "In NuSMV, INVARSPEC p means G p over one snapshot; hence startPrev and valvePrev."
        # NuSMV 靠**辅助状态变量**把上一拍存下来；我们没权改被测程序，
        # 就把它做成"求值期替换"——效果相同，且不改题目接口。
        text = _expand_prev(atom, prev_snap, lambda e, s: _eval_st(e, s))

        key = text
        if key not in cache:
            cache[key] = _parse_atom(text)
        node = cache[key]

        return _eval_st(node, snap, parse=False)

    def _eval_st(node_or_text, snap, parse: bool = True) -> Any:
        node = _parse_atom(node_or_text) if parse else node_or_text
        probe = Interpreter.__new__(Interpreter)
        probe.pou = None
        probe.types = interp_types
        probe.structs = structs
        probe.mem = dict(snap)
        probe.steps = 0
        probe.MAX_STEPS_PER_CYCLE = 10_000
        try:
            return probe.eval(node)
        except (SimError, SimulationTimeout, KeyError):
            # 原子命题里引用了快照中不存在的变量：属于**规约写错**，
            # 不该被当成"条件不满足"而静默通过。
            raise

    def ev_truthy(atom: str, snap: dict[str, Any], prev_snap: dict[str, Any] | None = None) -> bool:
        text = _expand_prev(atom, prev_snap, lambda e, s: _eval_st(e, s))
        if text not in cache:
            cache[text] = _parse_atom(text)
        probe = Interpreter.__new__(Interpreter)
        probe.pou = None
        probe.types = interp_types
        probe.structs = structs
        probe.mem = dict(snap)
        probe.steps = 0
        probe.MAX_STEPS_PER_CYCLE = 10_000
        return probe._truthy(probe.eval(cache[text]))

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
) -> CheckReport:
    """对有界轨迹集合做模型检查。

    ``specs`` 可以是 ``[(id, formula), …]`` 或 ``{id: formula}``。

    检查流程：
      1. 编译并静态检查（第一、二层：语法 + 类型）；
      2. 从初始状态出发，按输入空间广度优先展开状态图；
      3. 对每条**尚未检查过的轨迹前缀**跑 LTL，一旦违反就记下反例；
      4. 状态去重后，同一状态不重复展开。
    """
    deadline = time.monotonic() + max_seconds if max_seconds else None
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

    # ---- 解析规约（解析失败说明数据集有缺陷，要显式报出来）----
    parsed: list[tuple[str, str, LtlNode]] = []
    for sid, text in specs:
        try:
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

    # ---- 判定策略：能不能"边展开边逐拍判定"？----
    # 只有 G / X / prev / 布尔连接 / 原子命题 组成的公式，结论只依赖"这一拍和
    # 上一拍"：G φ 在位置 k 违反 ⟺ 某个位置 φ 为假，而这个位置在它成为
    # "窗口末拍"时就已经被判过了。所以可以每生成一拍就地判两个后缀
    # （倒数第二拍、末拍），**不必把每条轨迹都存下来事后重判**。
    # F / U / R 要看未来，必须等轨迹足够长，只能走"全存后判"的慢路。
    _WINDOWED = {"atom", "true", "false", "not", "and", "or", "impl", "iff", "X", "G", "prev"}

    def _only_windowed(node) -> bool:
        return node.kind in _WINDOWED and all(_only_windowed(a) for a in node.args)

    fast_judge = all(_only_windowed(nd) for _sid, _txt, nd in parsed)

    # 类型表来自 POU 声明（Interpreter 构造时自己会建，这里预先建一份给原子命题求值用）
    decl_types = {d.name.lower(): d.data_type for d in res.pou.decls}
    ev = _atom_evaluator(decl_types, res.structs)
    combos = list(itertools.islice(input_space.iter_combos(), max_traces))
    truncated = len(combos) < input_space.size()

    # ---- 第 2 步：广度优先展开状态图 ----
    # 队列元素：(状态键, 轨迹)。轨迹里每一项是"这一拍的输入 + 这一拍结束后的快照"，
    # 这样反例能原样重放，不用猜。
    input_names = {
        d.name.lower() for d in res.pou.decls if str(d.section).upper().startswith("VAR_INPUT")
    }
    bad = input_space.validate(input_names)
    if bad:
        rep.error = (
            "输入域里这些名字在程序中不存在：" + ", ".join(sorted(bad))
            + "；程序实际输入是：" + ", ".join(sorted(input_names))
        )
        return rep
    if not combos:
        rep.error = "输入空间为空，无法展开状态图"
        return rep

    fixed_names=tuple(n.lower() for n in input_space.fixed_inputs)
    rep.fixed_input_domains={n:list(values) for n,values in input_space.domains.items() if n.lower() in fixed_names}

    def binding(combo):
        values={n.lower():v for n,v in combo.items()}
        return tuple(_freeze(values[n]) for n in fixed_names)

    def state_key(it):
        # Equal PLC memory under different bindings can have different future transitions.
        return (_state_key(it),tuple(_freeze(it.get_var(n)) for n in fixed_names))

    starts: list[tuple[tuple, list[tuple[dict, dict]]]] = []
    # 首拍之前的快照 = 各变量的声明初值（PLC 上电瞬间的存储区）。它充当
    # 第 1 拍的 prev()，否则 "本拍没改变状态" 这类性质会被无意义地判假。
    _init_it = Interpreter(res.pou, res.structs)
    init_snap = snapshot(_init_it)
    scan_fail = 0
    for combo in combos:
        if deadline is not None and time.monotonic() >= deadline:
            truncated = True
            break
        it = Interpreter(res.pou, res.structs)
        try:
            for name, val in combo.items():
                it.set_var(name, val)
            it.scan()
        except (SimError, SimulationTimeout):
            scan_fail += 1
            continue
        snap = snapshot(it)
        key = state_key(it)
        starts.append((key, [(combo, snap)]))

    if not starts:
        rep.error = f"{len(combos)} 组首拍输入全部仿真失败，状态图无法展开"
        return rep

    results: dict[str, SpecResult] = {sid: SpecResult(spec_id=sid, formula=txt, holds=False, inconclusive=True) for sid, txt, _ in parsed}
    # 已确认违反的规约不再重复找反例，省掉绝大部分计算
    violated: set[str] = set()
    # 每条规约"已判定过的最长后缀长度"。inconclusive（信息不足）是**较弱**的结论，
    # 不能覆盖已经在更长轨迹上得到的确定结论——否则短后缀会把好结论冲掉。
    judged_len: dict[str, int] = {}

    # ---- 第 3 步：跑 LTL ----
    # **关键：从每个快照位置开始看，而不是只从第 1 拍看。**
    # LTL 的语义是 (π,k) ⊨ φ（课件第 35 页），而且真实检查器的做法是
    # "从每个可达状态出发"——被控对象里程序通常要跑好几拍才进入状态，
    # 只从第 1 拍判会把"还没来得及开阀"误读成"永远不会开阀"。
    def _check(trace: list[tuple[dict, dict]], pos: int) -> None:
        """检查轨迹第 pos 拍起的后缀。

        判定优先级（高 → 低）：**违反 > 确定成立 > 信息不足**。
        低优先级的结果绝不能覆盖高优先级，也不能用更短的后缀覆盖更长的后缀——
        否则"1 个快照的小后缀"会把"3 个快照判清楚的结论"冲成"界内无法判定"。
        """
        snaps = [snap for _inp, snap in trace]
        span = len(snaps) - pos + 1  # 这条后缀有多少个快照
        for sid, txt, node in parsed:
            if sid in violated:
                continue
            v: Verdict = evaluate(node, snaps, ev, start=pos, init_snapshot=init_snap)

            if not v.holds and not v.inconclusive:
                # 找到反例：最高优先级，直接定案
                results[sid] = SpecResult(
                    spec_id=sid,
                    formula=txt,
                    holds=False,
                    contradicting=True,
                    counterexample=snaps,
                    ce_at=v.counterexample_at,
                    explanation=explain(node, snaps, v.counterexample_at or 1),
                    bounded=False,
                    reason=v.reason,
                )
                violated.add(sid)
                continue

            cur = results[sid]
            if cur.contradicting:
                continue  # 已有反例，不必再动

            if v.inconclusive:
                # 信息不足：只有"更长的后缀"才有资格说话，且不能盖掉已确定成立的结论
                if cur.inconclusive and span > judged_len.get(sid, 0):
                    judged_len[sid] = span
                    results[sid] = SpecResult(
                        spec_id=sid, formula=txt, holds=True, inconclusive=True, reason=v.reason
                    )
                continue

            # 确定成立：可以覆盖"信息不足"（升级），但不能被更短的成立覆盖掉更长的记录
            if cur.inconclusive or span > judged_len.get(sid, 0):
                judged_len[sid] = span
                results[sid] = SpecResult(
                    spec_id=sid, formula=txt, holds=True, bounded=v.bounded, reason=v.reason
                )

    # 先把状态图**完整**展开，再统一判定。
    # 早期实现在展开过程中顺带判定并 early-stop，导致"前半段轨迹看过就跳过"，
    # 漏掉了 R4/R6 这类需要"先关后开"的迁移性质——图展开与判定必须解耦。
    # 去重：同一(状态, 位置)不必重复判定。位置参与是因为起点不同看到的后缀不同。
    visited: set[tuple] = set()
    # 状态图：用于 LTL 判定的轨迹都留在这里（每个状态留一条代表轨迹）
    traces: list[tuple[tuple, list[tuple[dict, dict]]]] = []
    queue: list[tuple[tuple, list[tuple[dict, dict]]]] = []

    for key, trace in starts:
        rep.traces_explored += 1
        if key not in visited:
            visited.add(key)
            if not fast_judge:
                traces.append((key, trace))
            queue.append((key, trace))
        if fast_judge:
            # 首拍只能从位置 1 判：它的 prev 是声明初值，语义上是对的
            _check(trace, 1)

    # ⚠️ 循环条件必须是 ``depth < max_depth``，**不能**写成 ``while queue``。
    # 状态图小（FB_Fill 只有 3 个状态）时第 2 层就没有新状态了，若照"没新状态就停"
    # 展开只有 2 拍——而 R4 需要 3 个快照（`X (X xValve)`）才判得出来。
    # 状态去重控制了**广度**（不重复展开），max_depth 控制了**深度**（轨迹够长），
    # 两者是两回事，不能互相顶替。
    # ⚠️⚠️ 2026-10-24 修的一个**性能事故**（务必读懂再改）：
    # 原实现把**每一条**生成的轨迹都塞进 queue 继续展开，理由是"历史不同"。
    # 这在 2~3 个输入的 FB_Fill 上没问题，但自建题有 4~5 个输入、组合数 144，
    # 于是第 d 层前沿有 144^d 条轨迹，6 拍就是 1e10 量级——实测单题跑 13 分钟不出结果。
    #
    # 正确做法是**历史窗口去重**：两条轨迹只要"最近 HISTORY 个快照"相同，
    # 对任何只往回看 HISTORY-1 拍的公式来说，它们从这一刻起的未来完全一样
    # （同一状态 + 同一输入序列 ⇒ 同一后续轨迹），保留一条代表即可。
    # 被丢掉的那条能发现的违反，代表轨迹也能发现。
    #
    # HISTORY 取 2：`prev()` 只需回看 1 拍，留 2 个快照就能可靠判定从第 k-1 拍
    # 起的所有后缀；取 1 会把 `G(a ∧ prev(¬a) → …)` 这类边沿性质判错。
    # 这与"状态去重"不是一回事：状态键只看末态，会丢掉 prev 需要的那一拍历史，
    # 实测漏掉 8 条反例；历史窗口去重保留恰好够用的历史，既不漏也不炸。
    depth = 1
    def temporal_span(node):
        return (1 if node.kind in ("X", "prev") else 0) + max((temporal_span(a) for a in node.args), default=0)
    HISTORY = max(2, 1 + max((temporal_span(n) for _, _, n in parsed), default=0))
    # 迁移记忆：(父窗口, 输入组合) -> (状态键, 快照) / None（该迁移仿真失败）
    memo: dict[tuple, tuple | None | int] = {}

    def _window(trace: list[tuple[dict, dict]]) -> tuple:
        """前沿去重键 = 最近 HISTORY 个快照的冻结形式。"""
        win = trace[-HISTORY:]
        return tuple(
            tuple((k, _freeze(v)) for k, v in sorted(snap.items())) for _inp, snap in win
        )

    while queue and rep.traces_explored < max_traces and depth < max_depth:
        if deadline is not None and time.monotonic() > deadline:
            truncated = True
            break
        depth += 1
        nxt: list[tuple[tuple, list[tuple[dict, dict]]]] = []
        seen_frontier: set[tuple] = set()
        stop = False
        for _key, trace in queue:
            if stop:
                break
            parent_key = _window(trace)
            for combo in combos:
                if fixed_names and binding(combo)!=binding(trace[0][0]):
                    continue
                if rep.traces_explored >= max_traces:
                    truncated = True
                    stop = True
                    break
                if deadline is not None and time.monotonic() > deadline:
                    truncated = True
                    stop = True
                    break
                # **迁移记忆化**：一次迁移只取决于"父状态 + 输入"，与怎么走到父状态
                # 无关（这正是历史窗口去重的前提）。不去记忆化就得为每个组合
                # 重新 replay 整条轨迹，实测 144 组合 × 6 层会把预算烧在重复计算上。
                ck = (parent_key, tuple(sorted(
                    (k, _freeze(v)) for k, v in combo.items()
                )))
                hit = memo.get(ck, 0)
                if hit == 0:
                    it = _replay(res, trace, combo)
                    if it is None:
                        scan_fail += 1
                        memo[ck] = None
                        continue
                    try:
                        it.scan()
                    except (SimError, SimulationTimeout):
                        scan_fail += 1
                        # 运行期错误是仿真层该报的东西，这里跳过继续找别的路径
                        memo[ck] = None
                        continue
                    snap = snapshot(it)
                    key = state_key(it)
                    memo[ck] = (key, snap)
                elif hit is None:
                    continue
                else:
                    key, snap = hit

                visited.add(key)
                fk = _window(trace + [(combo, snap)])
                # 同一个窗口 = 同一段历史，后面怎么看都一样：
                # 判定和继续展开都没必要重复做。这里同时省掉了判定开销和
                # traces_explored 的虚高（原先 6.8 万个状态却记了 6 万条轨迹）。
                if fast_judge and fk in seen_frontier:
                    continue
                seen_frontier.add(fk)
                rep.traces_explored += 1
                new_trace = trace + [(combo, snap)]
                # 慢路：轨迹一律留下来给第 4 步判定用（判定不看前沿去重）；
                # 快路：就地判"倒数第二拍 / 末拍"两个后缀，不保存轨迹
                if fast_judge:
                    for pos in range(max(1,len(new_trace)-HISTORY+1),len(new_trace)+1):
                        _check(new_trace,pos)
                else:
                    traces.append((key, new_trace))
                nxt.append((key, new_trace))

        queue = nxt
        if stop:
            break

    if queue and depth < max_depth and rep.traces_explored >= max_traces:
        truncated = True
    rep.states_explored = len(visited)
    rep.max_depth = depth
    rep.truncated = truncated
    if scan_fail:
        rep.error = f"{scan_fail} 条输入迁移发生运行期错误；不能报告规约通过"

    # ---- 第 4 步：跑 LTL（图展开结束之后）----
    # ⚠️ **判定阶段不能用状态键去重**。
    # 状态键相同只代表"末态相同"，但两条到达同一状态的轨迹历史不同，
    # 而 R3 这类性质恰恰问的是"变的那一刻，上一拍的 start 是什么"——
    # 拿状态键去重会把历史不同的轨迹当成同一条，直接漏掉反例（实测漏掉 8 条）。
    # 状态去重只用于控制**展开广度**（不重复展开），不用于判定。
    seen_judged: set[tuple] = set()
    for _key, trace in ([] if fast_judge else traces):
        # 不同轨迹只要快照序列不同就得判；用整条快照序列做去重键
        # _freeze 对普通 dict 不递归，必须逐项冻结（同 _trace_key 的处理）
        sig = tuple(
            tuple((k, _freeze(v)) for k, v in sorted(snap.items()))
            for _inp, snap in trace
        )
        if sig in seen_judged:
            continue
        seen_judged.add(sig)
        for pos in range(1, len(trace) + 1):
            _check(trace, pos)

    rep.states_explored = len(visited)
    rep.max_depth = depth

    # 没找到反例的规约：成立，但只是"界内成立"
    for sid, txt, node in parsed:
        r = results.get(sid)
        if r is None or r.contradicting:
            rep.specs.append(r or SpecResult(spec_id=sid, formula=txt, holds=True))
            continue
        rep.specs.append(
            SpecResult(
                spec_id=sid,
                formula=txt,
                holds=not r.inconclusive,
                bounded=True,
                inconclusive=r.inconclusive,
                reason=(
                    r.reason
                    if r.reason
                    else f"在 {rep.max_depth} 拍、{rep.states_explored} 个可达状态内未发现违反"
                ),
            )
        )

    return rep


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

# -*- coding: utf-8 -*-
"""LTL（线性时序逻辑）：解析 + 在**有界轨迹**上求值。

课程课件 S1_1 第 35 页给了 LTL 的语义定义：

    (π,k) ⊨ p        iff  p 在快照 s_k 为真
    (π,k) ⊨ X φ      iff  (π,k+1) ⊨ φ
    (π,k) ⊨ G φ      iff  对所有 j ≥ k，(π,j) ⊨ φ
    (π,k) ⊨ F φ      iff  存在 j ≥ k，(π,j) ⊨ φ
    (π,k) ⊨ φ U ψ    iff  存在 j ≥ k 使 (π,j) ⊨ ψ，且对所有 k ≤ i < j 有 (π,i) ⊨ φ

这里实现的是**有界（bounded）**版本：轨迹是有限长 π = s_1 … s_n。有限轨迹上
G 与 F 的判定是可靠的**反证工具**——

    * 有限轨迹可以**证伪** G φ：找到一个 k 使 φ 为假就够了；
    * 有限轨迹可以**证真** F φ：找到一个 k 使 φ 为真就够了；
    * "G φ 成立"在有限轨迹上**只能当近似证据**，因为更长的轨迹可能违反它。

课件第 37 页把这条讲得很清楚："One week can refute 'always', but never prove it."
所以本模块返回的不只是真假，还有 ``bounded`` 标记，告诉调用方这个结论的强度。
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Callable

# --------------------------------------------------------------------------
# 词法
# --------------------------------------------------------------------------

_TOKEN_RE = re.compile(
    r"""
    \s+
  | (?P<num>\d+\#[0-9A-Fa-f_]+|\d+\.\d+|\d+)
  | (?P<ident>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<cmp>>=|<=|<>|!=|==|=)
  | (?P<op><->|->|AND|OR|NOT|&&|\|\||!|&|\||~)
  | (?P<punct>[()<>.,\[\]:+\-*/])
  | (?P<bad>.)
    """,
    re.VERBOSE,
)


@dataclass
class Tok:
    kind: str  # num / ident / op / punct / eof
    text: str
    pos: int


class LTLParseError(ValueError):
    """规约写法不对——这属于**数据集缺陷**，不是模型写错代码。"""

    def __init__(self, msg: str, formula: str = "", pos: int = 0):
        self.pos = pos
        self.formula = formula
        caret = (" " * pos + "^") if formula else ""
        super().__init__(f"{msg}" + (f"\n  {formula}\n  {caret}" if formula else ""))


def _lex(src: str) -> list[Tok]:
    out: list[Tok] = []
    i = 0
    while i < len(src):
        m = _TOKEN_RE.match(src, i)
        if not m:
            raise LTLParseError(f"无法识别的字符 {src[i]!r}", src, i)
        kind = m.lastgroup or ""
        text = m.group(0)
        if kind == "":
            i = m.end()
            continue
        if kind == "bad":
            raise LTLParseError(f"无法识别的字符 {text!r}", src, i)
        out.append(Tok(kind, text, i))
        i = m.end()
    out.append(Tok("eof", "", len(src)))
    return out


# --------------------------------------------------------------------------
# 语法树
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class LtlNode:
    """LTL 公式节点。

    kind 取值：
      * ``atom``   原子命题（一个快照上求值的布尔表达式）
      * ``not`` / ``and`` / ``or`` / ``impl`` / ``iff``
      * ``X`` / ``F`` / ``G`` / ``U`` / ``R``
      * ``prev``   上一周期（课件 R3 用 startPrev 表达的"新按下"）
      * ``true`` / ``false``
    """

    kind: str
    args: tuple["LtlNode", ...] = ()
    text: str = ""  # 原子命题原文，用于报错和生成反例说明


TRUE = LtlNode("true")
FALSE = LtlNode("false")


# 数学符号 → ASCII。顺序重要：多字符（↔ →）必须先于单字符替换。
_UNICODE_OPS: tuple[tuple[str, str], ...] = (
    ("↔", " <-> "),
    ("→", " -> "),
    ("∧", " AND "),
    ("∨", " OR "),
    ("¬", "NOT "),
    ("□", "G"),
    ("◇", "F"),
    ("○", "X"),
    ("◯", "X"),
    ("◊", "F"),
    ("≠", " <> "),
    ("≤", " <= "),
    ("≥", " >= "),
)


def _join_atom(parts: list[str]) -> str:
    """把 token 拼回表达式文本。

    只在**标识符/数字与标识符/数字**之间补空格，符号之间不补：
    ``count >= 3`` 保持可读，``buffer[1]`` 不会被拆成 ``buffer [ 1 ]``。
    """
    out: list[str] = []
    prev_word = False
    for p in parts:
        is_word = bool(re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*|\d+(\.\d+)?", p))
        if out and prev_word and is_word:
            out.append(" ")
        out.append(p)
        prev_word = is_word
    return "".join(out)


# --------------------------------------------------------------------------
# 递归下降解析
# --------------------------------------------------------------------------
# 运算符优先级（由低到高）：
#   <->  ->  或  且  U/R  一元（NOT / G / F / X / prev）  原子
#
# 课件第 19 页的 R3 写作 ``G ((¬valve ∧X valve) → (¬start ∧X start))``，
# 说明 X 的结合力比 ∧ 强；这里按"A X 高优先级"实现。


class _Parser:
    def __init__(self, src: str):
        self.src = src
        self.toks = _lex(src)
        self.i = 0

    # ---- 基础 ----
    @property
    def cur(self) -> Tok:
        return self.toks[self.i]

    def peek(self, n: int = 1) -> Tok:
        return self.toks[min(self.i + n, len(self.toks) - 1)]

    def eat(self, text: str | None = None) -> Tok:
        t = self.cur
        if text is not None and t.text.upper() != text.upper():
            raise LTLParseError(f"期望 {text!r}，实际 {t.text!r}", self.src, t.pos)
        self.i += 1
        return t

    def accept(self, *texts: str) -> Tok | None:
        t = self.cur
        for want in texts:
            if t.text.upper() == want.upper():
                self.i += 1
                return t
        return None

    # ---- 文法 ----
    def parse(self) -> LtlNode:
        node = self.p_iff()
        if self.cur.kind != "eof":
            raise LTLParseError(f"多余的记号 {self.cur.text!r}", self.src, self.cur.pos)
        return node

    def p_iff(self) -> LtlNode:
        node = self.p_impl()
        while self.accept("<->", "↔"):
            node = LtlNode("iff", (node, self.p_impl()))
        return node

    def p_impl(self) -> LtlNode:
        node = self.p_or()
        if self.accept("->", "→"):
            # 右结合：a -> b -> c 视作 a -> (b -> c)
            return LtlNode("impl", (node, self.p_impl()))
        return node

    def p_or(self) -> LtlNode:
        node = self.p_and()
        while self.accept("OR", "||", "∨", "|"):
            node = LtlNode("or", (node, self.p_and()))
        return node

    def p_and(self) -> LtlNode:
        node = self.p_until()
        while self.accept("AND", "&&", "∧", "&"):
            node = LtlNode("and", (node, self.p_until()))
        return node

    def p_until(self) -> LtlNode:
        node = self.p_unary()
        # U / R 左结合，优先级高于 ∧（课件里 until 通常两侧是原子或括号）
        while True:
            t = self.cur
            if t.text.upper() == "U" and t.kind == "ident":
                self.i += 1
                node = LtlNode("U", (node, self.p_unary()))
            elif t.text.upper() == "R" and t.kind == "ident":
                self.i += 1
                node = LtlNode("R", (node, self.p_unary()))
            else:
                break
        return node

    def p_unary(self) -> LtlNode:
        t = self.cur
        up = t.text.upper()

        # Word operators can be lexed as identifiers. Keep temporal negation in
        # the LTL tree, including NOT(prev(...)) and NOT(rising(...)).
        if up in ("NOT", "!", "~", "¬"):
            self.i += 1
            return LtlNode("not", (self.p_unary(),))
        if t.kind == "ident" and up in ("G", "F", "X"):
            self.i += 1
            return LtlNode(up, (self.p_unary(),))
        if t.kind == "ident" and up == "PREV":
            self.i += 1
            if self.accept("("):
                inner = self.p_or()
                self.expect_rparen()
            else:
                inner = self.p_unary()
            return LtlNode("prev", (inner,))

        # ---- 边沿算子：rising(x) / falling(x) ----
        # 它们**不是**新算子，只是 prev 的语法糖，但必须在这里展开：
        #   rising(x)  ≡  x ∧ ¬prev(x)      （本拍为真、上一拍为假）
        #   falling(x) ≡  ¬x ∧ prev(x)
        # 之所以值得单独提供，是因为 PLC 里"新按下"是最高频的规约要素
        # （课件 R3「阀只在**新的** Start 按下时开」就是 rising(start)），
        # 而手写 `x AND NOT prev(x)` 极易漏掉 NOT 写成 `x AND prev(x)`。
        # prev 在首拍返回 False，故 rising 在首拍等价于 x 本身，
        # 与 PLC 上电首拍 R_TRIG 的行为一致。
        if t.kind == "ident" and up in ("RISING", "FALLING"):
            self.i += 1
            if self.accept("("):
                inner = self.p_or()
                self.expect_rparen()
            else:
                inner = self.p_unary()
            was = LtlNode("prev", (inner,))
            if up == "RISING":
                return LtlNode("and", (inner, LtlNode("not", (was,))))
            return LtlNode("and", (LtlNode("not", (inner,)), was))

        return self.p_atom()

    def expect_rparen(self) -> None:
        if not self.accept(")"):
            raise LTLParseError(
                f"括号不配对：缺少 ')'，遇到 {self.cur.text!r}", self.src, self.cur.pos
            )

    def p_atom(self) -> LtlNode:
        t = self.cur

        if t.text == "(":
            self.i += 1
            node = self.p_iff()
            self.expect_rparen()
            return node

        if t.kind == "ident" and t.text.upper() in ("TRUE", "FALSE"):
            self.i += 1
            return TRUE if t.text.upper() == "TRUE" else FALSE

        if t.kind in ("num", "ident"):
            # 原子命题：把整段"变量比较"原文收进来，交给 ST 求值器去算。
            # 这样 ''valve = TRUE''、''count >= 3''、''a AND NOT b'' 都能直接用。
            return self._collect_atom()

        raise LTLParseError(f"这里不该出现 {t.text!r}", self.src, t.pos)

    def _collect_atom(self) -> LtlNode:
        """把一段布尔表达式原文收成一个原子命题。

        规则：从当前记号开始向右扫，直到在**括号深度 0** 处遇到
        ``)`` / 顶层连接词 / 时序算子为止。括号内的内容整体收进来。

        为什么需要这么绕：``G (lsh -> NOT valve)`` 里 ``lsh -> NOT valve``
        是**命题式**蕴含（在同一个快照上求值），而 ``G`` 是**时序**算子。
        两者长得像，但含义完全不同，必须按上下文区分：出现在 G/F/X 之后、
        被括号包住的，里面的 -> 属于原子命题。
        """
        start = self.cur.pos
        depth = 0
        parts: list[str] = []
        _STOP_OPS = {"AND", "&&", "&", "OR", "||", "|", "U", "R"}
        _STOP_SYM = {"->", "<->"}
        _STOP_IDENT = {"AND", "OR", "U", "R"}

        while True:
            t = self.cur
            if t.kind == "eof":
                break
            up = t.text.upper()

            if depth == 0 and parts:
                # 顶层的右括号：属于外层分组，不收
                if t.text == ")":
                    break
                if t.kind == "op" and (up in _STOP_OPS or t.text in _STOP_SYM):
                    break
                if t.kind == "ident" and up in _STOP_IDENT:
                    break

            if t.text == "(":
                depth += 1
            elif t.text == ")":
                if depth == 0:
                    break
                depth -= 1
            parts.append(t.text)
            self.i += 1

        if not parts:
            raise LTLParseError("原子命题为空", self.src, start)
        return LtlNode("atom", text=_join_atom(parts))


def parse(src: str) -> LtlNode:
    """把 LTL 文本解析成语法树。支持 ``¬``/``∧``/``∨``/``→``/``↔`` 等数学符号。"""
    if not src or not src.strip():
        raise LTLParseError("LTL 公式为空")
    # 数学符号先归一化成 ASCII：课件（第 34-35 页）用 ¬∧∨→ 写公式，
    # 而学生和 LLM 提交通常用 !&|->。两种都得吃，否则会出现
    # "课件里的公式我们系统解析不了"这种荒唐事。
    s = src.strip()
    for a, b in _UNICODE_OPS:
        s = s.replace(a, b)
    return _Parser(s).parse()

# --------------------------------------------------------------------------
# 有界轨迹求值
# --------------------------------------------------------------------------
# 轨迹 π = [s_1, s_2, …, s_n]，每个 s_k 是一个快照：(memory, inputs, outputs)。
# 快照在实现上就是一个"变量名 -> 值"的字典视图，原子命题由调用方提供的
# ``eval_atom`` 回调去求值——这样 LTL 层不需要知道 ST 解释器长什么样。


@dataclass
class Verdict:
    """一条规约在一次运行上的判定结果。

    ``holds`` 表示公式在 (π, 1) 处是否成立。
    ``bounded`` 表示这个结论有多强：

      * ``bounded=False``：结论**可靠**。例如 G φ 被证伪时一定找到了具体快照；
        F φ 被证真时一定找到了具体快照。
      * ``bounded=True``：结论**只是近似**。例如有限轨迹上 G φ 为真，只能说
        "前 n 个快照没违反"，不能说 φ 永远成立。论文里必须这么写。
    """

    holds: bool
    bounded: bool = False
    # 反例：最先出问题的那一拍（1 基），以及它的成因
    counterexample_at: int | None = None
    reason: str = ""
    # 张力：F 因为轨迹不够长而没等到，需要加长轨迹才能下结论
    inconclusive: bool = False


def _atom_eval(
    node: LtlNode,
    snapshot: dict[str, Any],
    eval_atom: Callable[..., bool],
    prev_snapshot: dict[str, Any] | None = None,
) -> bool:
    if node.kind == "true":
        return True
    if node.kind == "false":
        return False
    # 求值器若声明自己能吃「上一拍快照」，就把 prev(x) 交给它展开；
    # 否则退回两参数调用（老调用方不受影响）。
    if getattr(eval_atom, "_accepts_prev", False):
        return eval_atom(node.text, snapshot, prev_snapshot)
    return eval_atom(node.text, snapshot)


def evaluate(
    formula: LtlNode | str,
    trace: list[dict[str, Any]],
    eval_atom: Callable[..., bool],
    *,
    start: int = 1,
    init_snapshot: dict[str, Any] | None = None,
) -> Verdict:
    """在有限轨迹上判定公式。

    ``start`` 是 1 基的起点（课件里 π ⊨ φ 定义为 (π,1) ⊨ φ）。
    ``init_snapshot`` 是**第一次扫描之前**的状态（声明初值），用作第 1 拍的
    "上一拍"。不给时退化为 None（``prev`` 取假）。
    """

    if isinstance(formula, str):
        formula = parse(formula)
    n = len(trace)

    class _Beyond(Exception):
        pass

    def at(k: int) -> dict[str, Any]:
        if k > n:
            raise _Beyond()
        return trace[k - 1]

    def prev_at(k: int) -> dict[str, Any] | None:
        """第 k 拍的"上一拍"快照。

        首拍的"上一拍"是**第一次扫描之前**的状态，也就是各变量的声明初值
        （PLC 上电瞬间的存储区）。这一点很关键：很多性质的真实含义是
        "本拍的操作没有改变状态"，在"快照=扫描结束后的状态"口径下应写成
        `G(guard -> x = prev(x))`。若把首拍的 prev 取成 None/假，这类性质
        在首拍会被无意义地判假（0 = FALSE）。

        没有提供 init_snapshot 时退化为 None（prev 取假），保持旧行为。
        """
        return trace[k - 2] if k >= 2 else init_snapshot

    def ev(node: LtlNode, k: int) -> bool:
        kind = node.kind

        if kind in ("atom", "true", "false"):
            return _atom_eval(node, at(k), eval_atom, prev_at(k))

        if kind == "not":
            return not ev(node.args[0], k)

        if kind == "and":
            return ev(node.args[0], k) and ev(node.args[1], k)

        if kind == "or":
            return ev(node.args[0], k) or ev(node.args[1], k)

        if kind == "impl":
            # a -> b 等价于 (NOT a) OR b；显式实现是为了短路，避免 b 的
            # 原子命题在 a 已经假的时候白算（大量变量时会慢很多）。
            return (not ev(node.args[0], k)) or ev(node.args[1], k)

        if kind == "iff":
            return ev(node.args[0], k) == ev(node.args[1], k)

        if kind == "X":
            return ev(node.args[0], k + 1)

        if kind == "prev":
            # 上一周期：k=1 时没有上一周期，按"未知"处理为 False——
            # PLC 上电首周期 prev 类变量就是初值，这里保持一致的保守语义。
            if k <= 1:
                return False
            return ev(node.args[0], k - 1)

        if kind == "G":
            sub = node.args[0]
            for j in range(k, n + 1):
                if not ev(sub, j):
                    return False
            return True

        if kind == "F":
            sub = node.args[0]
            for j in range(k, n + 1):
                if ev(sub, j):
                    return True
            raise _Beyond()

        if kind == "U":
            left, right = node.args
            for j in range(k, n + 1):
                if ev(right, j):
                    return True
                if not ev(left, j):
                    return False
            raise _Beyond()

        if kind == "R":
            # a R b ≡ NOT(NOT a U NOT b)
            left, right = node.args
            for j in range(k, n + 1):
                if not ev(right, j):
                    return False
                if ev(left, j):
                    return True
            # 轨迹走完了 b 一直成立，a 一次也没"释放"——有限轨迹上判不了
            raise _Beyond()

        raise LTLParseError(f"未知的 LTL 节点类型 {kind!r}")

    try:
        ok = ev(formula, start)
    except _Beyond:
        return Verdict(
            holds=False,
            bounded=True,
            inconclusive=True,
            reason=(
                f"轨迹只有 {n} 个快照，不足以判定该公式"
                "（F/U/R 需要更长的轨迹才能下结论）"
            ),
        )

    if not ok:
        # 定位最先出问题的**那一拍**：沿违反路径往下走，而不是拿前缀去试。
        # 例如 G(rain -> umbrella) 在第 4 天被打破，反例应报 4 而不是 1；
        # X umbrella 在第 2 天出问题，应报 2 而不是 1。
        ce = _locate_counterexample(formula, ev, start, n)
        return Verdict(
            holds=False,
            bounded=False,
            counterexample_at=ce,
            reason=f"在第 {ce} 个快照处违反",
        )

    # 结论为真 —— 判断强度
    bounded = _is_bounded_truth(formula)
    return Verdict(
        holds=True,
        bounded=bounded,
        reason=(
            "只有前若干个快照被检查过，不能当作'永远成立'的证明"
            if bounded
            else "在有限轨迹上可靠成立"
        ),
    )


def _is_bounded_truth(node: LtlNode) -> bool:
    """判断"公式为真"这个结论是否依赖轨迹长度。

    G 为真需要**所有**未来快照都满足，有限轨迹给不了这个保证 => 有界。
    F 为真只要一个见证快照 => 可靠。
    X 为真只看下一拍 => 可靠（只要还有下一拍）。

    课件第 37 页原话：One week can refute "always", but never prove it.
    """
    k = node.kind
    if k == "G":
        return True
    if k in ("true", "false", "atom", "prev"):
        return False
    if k == "not":
        # NOT(G φ) 为真 ⟺ G φ 为假 ⟺ 有反例，可靠
        return False
    if k in ("and", "or", "impl", "iff", "U", "R"):
        return any(_is_bounded_truth(a) for a in node.args)
    if k in ("F", "X"):
        return False
    return True


def _locate_counterexample(node: LtlNode, ev, start: int, n: int) -> int | None:
    """Locate decisive evidence without backdating a violated G obligation.

    For G, use its first failing body anchor as a lower bound. X may point
    to a later observation; prev contributes history to the obligation at
    its anchor. For Boolean combinations follow only evaluated operands.
    Evidence from both sides is needed for an equivalence mismatch.
    """
    def locate(cur, k, value):
        kind = cur.kind
        if kind == "G" and not value:
            sub = cur.args[0]
            for anchor in range(k, n + 1):
                if not ev(sub, anchor):
                    return max(anchor, locate(sub, anchor, False))
        if kind == "X":
            return locate(cur.args[0], k + 1, value)
        if kind == "prev":
            return k if k <= 1 else locate(cur.args[0], k - 1, value)
        if kind == "not":
            return locate(cur.args[0], k, not value)
        if kind in ("and", "or", "impl", "iff"):
            left, right = cur.args
            left_value = ev(left, k)
            left_at = locate(left, k, left_value)
            if kind == "and" and not left_value:
                return left_at
            if (kind == "or" and left_value) or (kind == "impl" and not left_value):
                return left_at
            # An AND/OR/implication reaching its right operand has the
            # right operand's value. For iff, both sides match iff value.
            right_value = (left_value == value) if kind == "iff" else value
            return max(left_at, locate(right, k, right_value))
        # An atomic assertion is observed at k. F/U/R retain their original
        # diagnostic convention of reporting the evaluation anchor.
        return k

    return max(start, min(n, locate(node, start, False)))


def explain(formula: LtlNode | str, trace: list[dict[str, Any]], at: int) -> str:
    """生成人类可读的反例说明：第 at 个快照的全部变量取值。"""
    if isinstance(formula, str):
        formula = parse(formula)
    snap = trace[at - 1]
    width = max((len(str(k)) for k in snap), default=0)
    rows = [f"      {str(k).ljust(width)} = {v}" for k, v in sorted(snap.items())]
    return "\n".join(
        [
            f"  反例出现在第 {at} 个快照（共 {len(trace)} 个）：",
            *rows,
        ]
    )

"""把自建题库导出成人可读的 Markdown。

为什么单独写导出脚本而不是手抄
------------------------------
题库的唯一真源是 ``datasets/selfmade/self-*.json``。手抄一份 Markdown 必然与 JSON
漂移——改了用例忘了改文档，是最典型的数据集事故。所以这里**每次从 JSON 现生成**，
只做排版，不引入任何人工内容。

字段口径（对着 schema.VarDef / Spec / TestCase 实测过）
-----------------------------------------------------
* ``VarDef``: name / data_type / description / direction / fields
* ``Spec``:   sid / text / ltl / kind / verified_by
* ``TestCase``: tc_id / inputs / expected / note / const_inputs / init / mode / cycles

用例表设计
----------
题目里的 ``test_cases`` 每个元素是**一个周期**（``mode`` 字段区分 single/sequence）。
如果 sequence 模式的每个周期都单独成行，表格会很长但信息最全；这里按 ``tc_id``
分组：同一 tc_id 的周期合并成一张"逐周期轨迹表"，不同 tc_id 各一张表。
"""

from __future__ import annotations

import sys
from collections import OrderedDict
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
DATASET = ROOT / "datasets" / "selfmade"

# 直接用 `python scripts/export_bank.py` 跑时，脚本目录不在 sys.path 里，
# 需要把项目根塞进去才能 import stbench。
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from stbench.schema import Problem  # noqa: E402


# ---------------------------------------------------------------- 工具

def _fmt(v: Any) -> str:
    """把变量值渲染成表格里好读的形式。"""
    if v is None:
        return "—"
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, float):
        return f"{v:g}"
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(_fmt(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ", ".join(f"{k}={_fmt(x)}" for k, x in v.items()) + "}"
    return str(v)


def _dir_name(d: Any) -> str:
    v = getattr(d, "value", d)
    return {
        "input": "输入",
        "output": "输出",
        "inout": "输入输出",
        "local": "内部",
        "in_out": "输入输出",
    }.get(str(v), str(v))


def _spec_kind(k: Any) -> str:
    """Spec.kind 是字符串，可能是 safety / liveness / ...，给个中文标签。"""
    return {"safety": "安全性", "liveness": "活性", "invariant": "不变式"}.get(str(k), str(k))


def _row(cells: list[str]) -> str:
    return "| " + " | ".join(cells) + " |"


def render_cases(problem: Problem) -> str:
    """把一个题的 test_cases 渲染成若干张表。"""
    cases = list(problem.test_cases)
    if not cases:
        return "_（无测试用例）_\n"

    # 列只取**实际在用例里出现过的**键，并保持接口声明顺序。
    #
    # 为什么不直接列全部接口变量：接口有 10 个变量、某个用例只用 3 个，
    # 剩下 7 个渲染成 "—"，读者分不清是"值为 None"还是"本题不涉及"。
    # 而 const_inputs 里给的量必须让人看到，所以也算"出现过"。
    declared_in = [v.name for v in problem.variables if _dir_name(v.direction) == "输入"]
    declared_out = [v.name for v in problem.variables if _dir_name(v.direction) == "输出"]

    used_in: set[str] = set()
    used_out: set[str] = set()
    for c in cases:
        used_in |= set(c.inputs or {})
        used_in |= set(c.const_inputs or {})
        used_out |= set(c.expected or {})

    names_in = [n for n in declared_in if n in used_in] + sorted(used_in - set(declared_in))
    names_out = [n for n in declared_out if n in used_out] + sorted(used_out - set(declared_out))

    # 按 tc_id 分组，保持出现顺序
    groups: "OrderedDict[str, list]" = OrderedDict()
    for c in cases:
        groups.setdefault(c.tc_id or "case", []).append(c)

    out: list[str] = []
    multi = len(groups) > 1
    for gid, group in groups.items():
        if multi:
            mode = group[0].mode or "single"
            out.append(f"**用例 `{gid}`**（{len(group)} 周期，mode=`{mode}`）\n")
        head = ["周期"] + names_in + names_out
        out.append(_row(head))
        out.append("|" + "|".join(["---"] * len(head)) + "|")
        for i, c in enumerate(group, 1):
            inp = c.inputs or {}
            exp = c.expected or {}
            # 本周期没显式给、但有常量兜底的输入，仍然按常量填，
            # 否则读者会以为这个周期该变量"没参与"
            consts_c = c.const_inputs or {}
            cells = [str(i)]
            cells += [_fmt(inp[k] if k in inp else consts_c.get(k)) for k in names_in]
            cells += [_fmt(exp.get(k)) for k in names_out]
            out.append(_row(cells))
        out.append("")

        # init / const_inputs 是"用例前置状态"，不写出来会让人误以为每周期都从零开始
        notes = []
        init = group[0].init or {}
        consts = group[0].const_inputs or {}
        if init:
            notes.append("**初始值**：" + "，".join(f"`{k}={_fmt(v)}`" for k, v in init.items()))
        if consts:
            notes.append("**常值输入**（不随周期变化）：" + "，".join(f"`{k}={_fmt(v)}`" for k, v in consts.items()))
        if notes:
            out.append("　".join(notes) + "\n")
    return "\n".join(out)


def render_problem(p: Problem, idx: int) -> str:
    out: list[str] = []
    diff = getattr(p.difficulty, "value", str(p.difficulty))
    out.append(f"## {idx}. `{p.pid}` — {p.title}\n")
    out.append(f"| 难度 | 用例模式 | 用例数 | 目标 POU |")
    out.append(f"|---|---|---|---|")
    out.append(f"| {diff} | `{p.case_mode}` | {len(p.test_cases)} | `{p.target_pou}` |")
    out.append("")

    out.append("### 接口定义\n")
    out.append("| 变量 | 方向 | 类型 | 说明 |")
    out.append("|---|---|---|---|")
    for v in p.variables:
        out.append(_row([f"`{v.name}`", _dir_name(v.direction), f"`{v.data_type}`", v.description or ""]))
    out.append("")

    out.append("### 控制要求\n")
    out.append(p.requirements.strip() + "\n")

    if p.specs:
        out.append("### LTL 规约（形式化验收条件）\n")
        out.append("| # | 类别 | 表达式 | 验证方式 |")
        out.append("|---|---|---|---|")
        for s in p.specs:
            out.append(_row([s.sid, _spec_kind(s.kind), f"`{s.ltl}`", s.verified_by or ""]))
            if s.text:
                out.append(_row(["", "", f"_{s.text}_", ""]))
        out.append("")

    out.append("### 测试用例\n")
    out.append(render_cases(p))
    return "\n".join(out)


def main() -> int:
    files = sorted(DATASET.glob("self-*.json"))
    if not files:
        print("没有找到自建题", file=sys.stderr)
        return 1

    problems = [Problem.load(f) for f in files]
    order = {"easy": 0, "medium": 1, "hard": 2}
    problems.sort(key=lambda p: (order.get(getattr(p.difficulty, "value", str(p.difficulty)), 9), p.pid))

    md: list[str] = []
    md.append(f"# 自建题库（{len(problems)} 道）\n")
    md.append("> 本文件由 `scripts/export_bank.py` 从 `datasets/selfmade/self-*.json` 自动生成。")
    md.append("> **不要手改**——下次导出会覆盖。真实修改请改 JSON 后重新导出：\n")
    md.append("> ```\n> python -X utf8 scripts/export_bank.py\n> ```\n")

    md.append("## 一览\n")
    md.append("| # | 题号 | 标题 | 难度 | 用例数 |")
    md.append("|---|---|---|---|---|")
    for i, p in enumerate(problems, 1):
        diff = getattr(p.difficulty, "value", str(p.difficulty))
        md.append(_row([str(i), f"`{p.pid}`", p.title, diff, str(len(p.test_cases))]))
    md.append("")

    total = sum(len(p.test_cases) for p in problems)
    md.append(f"合计 **{len(problems)}** 道题、**{total}** 个周期的测试向量。")
    md.append("每题都配有一份参考解（`datasets/selfmade/tests/*.reference.st`），")
    md.append("参考解必须本机跑通全部用例——这是数据集的质量闸门。\n")
    md.append("---\n")

    for i, p in enumerate(problems, 1):
        md.append(render_problem(p, i))
        md.append("\n---\n")

    out = ROOT / "docs" / "自建题库.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(md), encoding="utf-8")
    print(f"已导出 {len(problems)} 道题 / {total} 个周期 → {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

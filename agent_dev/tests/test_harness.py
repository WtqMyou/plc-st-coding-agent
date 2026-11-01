"""harness / providers 的回归测试。

为什么这些测试值得写：它们是**实验可信度的地基**。
如果"改错重试"其实没把诊断回灌给模型，或者代码抽取把回答吃掉了半截，
实验表上的通过率就是假的——而这种错误不会抛异常，只会悄悄把数字抬高。
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from stbench.harness.runner import Solver, solve_problem, summarize  # noqa: E402
from stbench.providers.base import extract_code, get_provider, ProviderError  # noqa: E402
from stbench.providers.mock import MockProvider  # noqa: E402
from stbench.schema import Problem  # noqa: E402
from stbench.selfmade_refs import REFS  # noqa: E402

PASS, FAIL = [], []


def check(name: str, cond: bool, detail: str = "") -> None:
    (PASS if cond else FAIL).append(name)
    print(f"[{'PASS' if cond else 'FAIL'}] {name}" + (f"  ({detail})" if detail and not cond else ""))


def test_extract_code() -> None:
    # 模型最常见的回法：一段说明 + 一个围栏
    t = "好的，实现如下：\n```st\nFUNCTION_BLOCK FB\nEND_FUNCTION_BLOCK\n```\n以上。"
    check("extract_包围栏", extract_code(t).startswith("FUNCTION_BLOCK"))

    # 没有围栏但有 FB 关键字：整篇当代码
    check("extract_无围栏", "FUNCTION_BLOCK" in extract_code("FUNCTION_BLOCK FB\nEND_FUNCTION_BLOCK"))

    # 两个围栏：优先带 st 标记的，即使它更短
    t2 = "```\nx := 1;\n```\n完整版：\n```st\nFUNCTION_BLOCK FB\nA: INT;\nEND_FUNCTION_BLOCK\n```"
    got = extract_code(t2)
    check("extract_优先st标记", got.startswith("FUNCTION_BLOCK") and "x := 1" not in got)


def test_provider_factory() -> None:
    try:
        get_provider("不存在的通道:x")
        check("provider_未知类型报错", False)
    except ProviderError:
        check("provider_未知类型报错", True)


def test_one_shot_path() -> None:
    p = Problem.load(ROOT / "datasets" / "selfmade" / "self-easy-01.json")
    s = Solver(MockProvider(script="echo_reference", reference=REFS["self-easy-01"]), max_iters=3)
    rec = solve_problem(p, s)
    check("oneshot_参考解一次通过", rec.solved and rec.first_try and len(rec.attempts) == 1)


def test_iterative_path() -> None:
    """第一轮故意写成接口不全，验证"诊断被回灌且能纠正"。"""
    p = Problem.load(ROOT / "datasets" / "selfmade" / "self-easy-01.json")
    bad = (
        "FUNCTION_BLOCK FB\n"
        "VAR_INPUT\n enable : BOOL;\nEND_VAR\n"
        "VAR_OUTPUT\n avgOut : REAL;\nEND_VAR\n"
        "avgOut := 1.0;\n"
        "END_FUNCTION_BLOCK"
    )
    s = Solver(MockProvider(script=[f"```st\n{bad}\n```", REFS["self-easy-01"]]), max_iters=3)
    rec = solve_problem(p, s)
    check("iterative_两轮解出", rec.solved and not rec.first_try and len(rec.attempts) == 2)
    check("iterative_失败轮有诊断", bool(rec.attempts[0].feedback) and "avgenable" in rec.attempts[0].feedback)
    # 关键：反馈里不能出现期望值，否则等于泄露答案
    check("iterative_反馈不泄期望值", "7.5" not in rec.attempts[0].feedback and "4.0" not in rec.attempts[0].feedback)


def test_summary_metrics() -> None:
    p = Problem.load(ROOT / "datasets" / "selfmade" / "self-easy-02.json")
    s = Solver(MockProvider(script="echo_reference", reference=REFS["self-easy-02"]), max_iters=2)
    rec = solve_problem(p, s)
    m = summarize([rec])
    check("summary_口径齐备", {"solve_rate", "first_try_rate", "compile_rate", "avg_iters"} <= set(m))


def main() -> int:
    test_extract_code()
    test_provider_factory()
    test_one_shot_path()
    test_iterative_path()
    test_summary_metrics()
    print(f"\n{len(PASS)}/{len(PASS) + len(FAIL)} 通过")
    return 0 if not FAIL else 1


if __name__ == "__main__":
    raise SystemExit(main())

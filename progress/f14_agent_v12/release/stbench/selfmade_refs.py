"""参考解：15 道自建题的标准答案，使用已冻结文件验证用例表自洽。

为什么要有这个文件
------------------
测试表和规约很容易写成"看起来对、实际自相矛盾"——例如断言 a6 期望
``highHigh = True`` 却没在 a5 里制造 ``sensorOK = FALSE`` 的转移。这类错误
用眼睛看不出来，但会让模型明明写对也判错，指标就没有意义了。

所以每道题的参考解都必须**本机跑通全部用例**。跑不通只有两种可能：
题目/用例写错了，或者参考解写错了——两种情况都必须当场修掉。
这是数据质量最省事的一道闸门，成本几乎为零。

用法
----
    python -X utf8 stbench/selfmade_refs.py          # 全部跑一遍，打印通过率
    python -X utf8 stbench/selfmade_refs.py --save   # 同时写进 datasets/selfmade/*.json 的 tests/reference.st

注意：参考解**不进提示词**。它只用于验证用例表、以及在报告里说明"用例是
可满足的"。给模型看参考解就等于泄题，没有任何意义。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import sys as _sys  # noqa: E402
_sys.path.insert(0, str(ROOT / "datasets"))

from selfmade_cases import CASES  # noqa: E402
from stbench.schema import Problem, TestCase  # noqa: E402
from stbench.st.driver import verify, verify_sequence  # noqa: E402

SELF_DIR = ROOT / "datasets" / "selfmade"


# One canonical source: delivered reference files. No in-memory test patching.
REFS = {f.name.replace(".reference.st", ""): f.read_text(encoding="utf-8")
        for f in sorted((SELF_DIR / "tests").glob("self-*.reference.st"))}


def patch_problem(p: Problem) -> Problem:
    """Compatibility API; frozen JSON is the source of truth and is not rewritten."""
    return p


def run_all(save: bool = False, verbose: bool = True) -> int:
    bad = 0
    total_cases = 0
    passed_cases = 0
    for pid, src in REFS.items():
        path = SELF_DIR / f"{pid}.json"
        p = patch_problem(Problem.load(path))
        res = (
            verify_sequence(src, p, "sequence")
            if p.case_mode == "sequence"
            else verify(src, p)
        )
        total_cases += res.tests_total
        passed_cases += res.tests_passed
        ok = res.compiles and res.all_tests_passed
        if verbose:
            flag = "OK  " if ok else "FAIL"
            print(f"[{flag}] {pid:16s} 编译={'√' if res.compiles else '×'} "
                  f"用例 {res.tests_passed}/{res.tests_total}")
            if not ok:
                for c in res.cases:
                    if not c.passed:
                        print(f"        {c.tc_id}: {c.message}")
                if not res.compiles:
                    print(f"        {res.failure_summary}")
        if not ok:
            bad += 1
        if save:
            out = path.parent / "tests"
            out.mkdir(parents=True, exist_ok=True)
            (out / f"{pid}.reference.st").write_text(src, encoding="utf-8")
            p.save(path)
    if verbose:
        print(f"\n参考解通过 {len(REFS) - bad}/{len(REFS)} 题，"
              f"用例 {passed_cases}/{total_cases}")
    return 0 if bad == 0 else 1


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="跑自建题参考解，验证用例表自洽")
    ap.add_argument("--save", action="store_true", help="同时写回题目 JSON 与参考解文件")
    args = ap.parse_args(argv)
    return run_all(save=args.save)


if __name__ == "__main__":
    sys.exit(main())

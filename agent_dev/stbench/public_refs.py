"""公共题参考解：20 道公共题的"标准答案"与回归闸门。

与 ``stbench/selfmade_refs.py`` 的分工
------------------------------------
自建题的参考解直接写在 Python 模块里（``REFS`` 常量），因为它们与用例表是
同一批人在同一个文件里维护的；公共题的参考解有 20 份 ST 源码、且要经得起
"换一个人也能重跑"的检查，所以落成**文件**：

    datasets/public/tests/<pid>.reference.st

本模块只做三件事：

1. 把参考解按 pid 装成 ``REFS`` 字典，供实验脚本的 mock 通道
   （``run_experiment.py --mock-use-refs``）验证全链路；
2. ``run_all()`` 逐题跑 编译 → 用例 → （可选）有界模型检查，作为"用例表是否
   自洽"的闸门——用例写错时它一定会红，这是最省事的数据质量检查；
3. 打印每题的统计，供报告表格直接取数。

参考解**不进提示词**，只用于验证用例与规约的可满足性；给模型看就等于泄题。

用法::

    python -X utf8 stbench/public_refs.py            # 全部 20 题
    python -X utf8 stbench/public_refs.py --pid public-easy-01 --mc
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from stbench.schema import Problem  # noqa: E402
from stbench.st.driver import verify, verify_sequence  # noqa: E402

PUBLIC_DIR = ROOT / "datasets" / "public"
TESTS_DIR = PUBLIC_DIR / "tests"


def _load_refs() -> dict[str, str]:
    refs: dict[str, str] = {}
    if not TESTS_DIR.is_dir():
        return refs
    for f in sorted(TESTS_DIR.glob("*.reference.st")):
        pid = f.name[: -len(".reference.st")]
        refs[pid] = f.read_text(encoding="utf-8")
    return refs


REFS: dict[str, str] = _load_refs()


def problem_files() -> list[Path]:
    return [f for f in sorted(PUBLIC_DIR.glob("*.json")) if not f.name.startswith("_")]


def run_all(pid: str = "", mc: bool = True, verbose: bool = True) -> int:
    """逐题跑参考解。返回失败题数（0 = 全绿）。"""
    bad = 0
    total_cases = passed_cases = 0
    specs_total = specs_hold = specs_viol = 0

    files = problem_files()
    if pid:
        files = [f for f in files if f.stem == pid]
        if not files:
            print(f"找不到题目 {pid}", file=sys.stderr)
            return 1

    for f in files:
        p = Problem.load(f)
        src = REFS.get(p.pid)
        if src is None:
            print(f"[MISS] {p.pid:18s} 缺少参考解 {TESTS_DIR / (p.pid + '.reference.st')}")
            bad += 1
            continue
        if not p.test_cases:
            print(f"[MISS] {p.pid:18s} 还没有测试用例")
            bad += 1
            continue

        if p.case_mode == "sequence":
            # sequence 题的轨迹语义与 MC 的"任意输入序列"不同，MC 单独在
            # verify() 路径上跑（同一份源码、单实例语义），两者结论分开记。
            res = verify_sequence(src, p)
            mc_res = verify(src, p) if mc else None
        else:
            res = mc_res = verify(src, p, model_check=mc)

        total_cases += res.tests_total
        passed_cases += res.tests_passed
        if mc_res is not None and not mc_res.mc_error:
            specs_total += mc_res.mc_specs_total
            specs_hold += mc_res.mc_specs_hold
            specs_viol += mc_res.mc_specs_violated

        ok = res.compiles and res.tests_passed == res.tests_total
        if mc_res is not None and not mc_res.mc_error:
            ok = ok and mc_res.mc_specs_violated == 0
        if verbose:
            flag = "OK  " if ok else "FAIL"
            extra = ""
            if mc_res is not None and not mc_res.mc_error:
                extra = (f" LTL={mc_res.mc_specs_total} hold={mc_res.mc_specs_hold} "
                         f"viol={mc_res.mc_specs_violated} incon={mc_res.mc_specs_inconclusive}")
            elif mc_res is not None and mc_res.mc_error:
                extra = f" MC_err={mc_res.mc_error[:40]}"
            print(f"[{flag}] {p.pid:18s} 编译={'√' if res.compiles else '×'} "
                  f"用例 {res.tests_passed}/{res.tests_total}{extra}")
            if not res.compiles:
                print(f"        {res.failure_summary}")
            for c in res.cases:
                if not c.passed:
                    print(f"        {c.hint or (c.tc_id + ': ' + c.message)}")
            if mc_res is not None:
                for v in mc_res.mc_violations[:3]:
                    print(f"        LTL 违反 {v['id']}: {v['formula']} @ {v['at']}")
        if not ok:
            bad += 1

    if verbose:
        n = len(files)
        print(f"\n公共题参考解通过 {n - bad}/{n} 题，用例 {passed_cases}/{total_cases}")
        if specs_total:
            print(f"LTL：{specs_total} 条，hold={specs_hold} viol={specs_viol}")
    return bad


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="跑公共题参考解，验证用例表自洽")
    ap.add_argument("--pid", default="", help="只跑一道题")
    ap.add_argument("--no-mc", action="store_true", help="跳过有界模型检查")
    ap.add_argument("--save", action="store_true", help="预留：参考解已按文件维护，无操作")
    args = ap.parse_args(argv)
    return 0 if run_all(args.pid, mc=not args.no_mc) == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())

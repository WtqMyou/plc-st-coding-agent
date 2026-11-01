"""单题验证：编译 + 用例 + 有界模型检查，一次看全。

用法（Windows 下务必带 -X utf8）：::

    python -X utf8 scripts/verify_one.py public-easy-01
    python -X utf8 scripts/verify_one.py public-hard-02 --no-mc   # 迭代用例时跳过 MC

参考解路径固定为 ``datasets/public/tests/<pid>.reference.st``（找不到时回退
``datasets/selfmade/tests/<pid>.reference.st``），与 ``check_dataset.py --pid
--ref`` 用的是同一份代码、同一套判定，区别只是这里会把模型检查的统计一起
打出来，方便判断 LTL 规约本身写没写对。

退出码：0 = 编译通过且用例全过；1 = 有失败；2 = 题目或参考解不存在。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from stbench.schema import Problem
from stbench.st.driver import verify, verify_sequence

PUB = ROOT / "datasets" / "public"
SELF = ROOT / "datasets" / "selfmade"


def main() -> int:
    ap = argparse.ArgumentParser(description="验证一道题的参考解（编译+用例+MC）")
    ap.add_argument("pid")
    ap.add_argument("--no-mc", action="store_true", help="跳过有界模型检查（迭代用例时更快）")
    ap.add_argument("--ref", type=Path, help="显式指定参考解路径")
    args = ap.parse_args()

    pid = args.pid
    f = PUB / f"{pid}.json"
    if not f.exists():
        f = SELF / f"{pid}.json"
    if not f.exists():
        print(f"找不到题目 {pid}", file=sys.stderr)
        return 2

    p = Problem.load(f)
    ref = args.ref or PUB / "tests" / f"{pid}.reference.st"
    if not ref.exists():
        ref = SELF / "tests" / f"{pid}.reference.st"
    if not ref.exists():
        print(f"缺少参考解：{PUB / 'tests' / (pid + '.reference.st')}", file=sys.stderr)
        return 2

    code = ref.read_text(encoding="utf-8")
    if not p.test_cases:
        print(f"{pid}: 还没有测试用例", file=sys.stderr)
        return 1

    from stbench.evaluation import evaluate, verification_status
    res = evaluate(code, p, model_check=not args.no_mc, timeout_s=p.mc_max_seconds+2)

    print(f"{pid}  case_mode={p.case_mode}  用例 {res.tests_passed}/{res.tests_total}  "
          f"本地静态检查 {'通过' if res.compiles else '失败'}")
    for d in res.compile_errors[:8]:
        print(f"   编译诊断: {d}")
    for c in res.cases:
        if not c.passed:
            print(f"   ✗ {c.hint or (c.tc_id + ': ' + c.message)}")
    if not args.no_mc:
        print(f"   LTL 状态: {verification_status(res)}")
        if res.mc_error:
            print(f"   MC: {res.mc_error}")
        else:
            print(f"   MC: specs={res.mc_specs_total} hold={res.mc_specs_hold} "
                  f"viol={res.mc_specs_violated} incon={res.mc_specs_inconclusive} "
                  f"states={res.mc_states} traces={res.mc_traces}")
            for v in res.mc_violations:
                print(f"   ✗ LTL 违反 {v['id']}: {v['formula']}  @ {v['at']}")
    return 0 if (res.all_tests_passed and res.compiles and (args.no_mc or res.specs_all_hold)) else 1


if __name__ == "__main__":
    raise SystemExit(main())

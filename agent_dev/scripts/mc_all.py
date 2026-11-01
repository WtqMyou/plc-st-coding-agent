# -*- coding: utf-8 -*-
"""批量跑「参考解 + 用例 + 有界模型检查」，把每条 LTL 规约的结论汇总成一行。

用途：确认数据集自洽——**参考解必须同时满足用例与它自己的规约**。参考解跑不过
用例说明用例写错了；参考解跑过用例但违反规约，说明规约写错了（或规约写的是参考
解之外的正确性要求）。两类错都只有跑一遍才看得见。

用法（Windows 下务必带 -X utf8）::

    python -X utf8 scripts/mc_all.py                    # 默认：10 道自建题
    python -X utf8 scripts/mc_all.py --set public       # 20 道公共题
    python -X utf8 scripts/mc_all.py --set all --depth 6
    python -X utf8 scripts/mc_all.py self-hard-03       # 只跑一题

退出码：0 = 全部 hold 且用例全过；1 = 有条目被违反/异常；2 = 参数或数据缺失。

注意两件事，否则会得到假失败：

1. 自建题必须走 ``selfmade_refs.patch_problem``：它给结构体输入补齐字段用例，
   不做这一步模型检查会因为输入域缺字段直接报错。
2. ``case_mode=="sequence"`` 的题要走 ``verify_sequence``，不能当单周期跑；
   序列题的模型检查用 ``_attach_model_check`` 单独挂上去。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from stbench.schema import Problem  # noqa: E402
from stbench.st.driver import verify, verify_sequence, _attach_model_check  # noqa: E402


def _selfmade(pid: str) -> tuple[Problem, str]:
    from stbench.selfmade_refs import REFS, patch_problem, SELF_DIR

    return patch_problem(Problem.load(SELF_DIR / f"{pid}.json")), REFS[pid]


def _public(pid: str) -> tuple[Problem, str]:
    p = Problem.load(ROOT / "datasets" / "public" / f"{pid}.json")
    ref = ROOT / "datasets" / "public" / "tests" / f"{pid}.reference.st"
    if not ref.exists():
        raise FileNotFoundError(f"缺少参考解 {ref}")
    return p, ref.read_text(encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description="批量验证参考解（用例 + 有界模型检查）")
    ap.add_argument("only", nargs="?", help="只跑这一道题")
    ap.add_argument("--set", default="selfmade", choices=["selfmade", "public", "all"])
    ap.add_argument("--depth", type=int, help="覆盖题目的 mc_max_depth（调试用）")
    args = ap.parse_args()

    jobs: list[tuple[str, str]] = []
    if args.set in ("selfmade", "all"):
        from stbench.selfmade_refs import REFS

        jobs += [("selfmade", pid) for pid in sorted(REFS)]
    if args.set in ("public", "all"):
        jobs += [("public", f.stem) for f in sorted((ROOT / "datasets" / "public").glob("public-*.json"))]
    if args.only:
        jobs = [(s, p) for s, p in jobs if p == args.only]
    if not jobs:
        print("没有可跑的题目", file=sys.stderr)
        return 2

    tot = {"specs": 0, "hold": 0, "viol": 0, "incon": 0, "sim": 0, "trunc": 0}
    bad: list[tuple[str, str, str]] = []

    for kind, pid in jobs:
        try:
            p, src = (_selfmade if kind == "selfmade" else _public)(pid)
        except FileNotFoundError as e:
            print(f"[MISS] {pid:16s} {e}", flush=True)
            bad.append((pid, "MISS", str(e)))
            continue
        if args.depth:
            p.mc_max_depth = args.depth

        if p.case_mode == "sequence":
            rep = verify_sequence(src, p, "sequence")
            _attach_model_check(src, p, rep)
        else:
            rep = verify(src, p, model_check=True)

        n_mc = sum(1 for s in p.specs if (s.ltl or "").strip())
        n_sim = len(p.specs) - n_mc
        tot["specs"] += n_mc
        tot["sim"] += n_sim
        if rep.mc_truncated:
            tot["trunc"] += 1

        cases = f"{rep.tests_passed}/{rep.tests_total}"
        if rep.mc_error:
            print(f"[MCERR] {pid:16s} cases={cases} {rep.mc_error}", flush=True)
            bad.append((pid, "MCERR", rep.mc_error))
            continue

        tot["hold"] += rep.mc_specs_hold
        tot["viol"] += rep.mc_specs_violated
        tot["incon"] += rep.mc_specs_inconclusive
        ok = rep.specs_all_hold and rep.all_tests_passed and rep.compiles
        if not ok and not rep.mc_violations:
            bad.append((pid,"INCOMPLETE","Truncated/inconclusive/functional failure; not verified"))
        flag = "OK  " if ok else "FAIL"
        trunc = " trunc=1" if rep.mc_truncated else ""
        print(
            f"[{flag}] {pid:16s} cases={cases} states={rep.mc_states:6d} "
            f"traces={rep.mc_traces:7d} ltl={n_mc} sim={n_sim} "
            f"hold={rep.mc_specs_hold} viol={rep.mc_specs_violated} "
            f"incon={rep.mc_specs_inconclusive}{trunc}",
            flush=True,
        )
        for v in rep.mc_violations:
            bad.append((pid, v["id"], v["explanation"]))
            print(f"        ! {v['id']} @ {v['at']}: {v['explanation'][:300]}", flush=True)

    print(
        "\n合计 LTL %d 条（另 %d 条 simulation-only）: hold=%d viol=%d incon=%d"
        % (tot["specs"], tot["sim"], tot["hold"], tot["viol"], tot["incon"]),
        flush=True,
    )
    print(f"truncated 题数（预算内未发现违反，不等于已验证）: {tot['trunc']}")
    print("失败条目:", len(bad), " 失败题数:", len({b[0] for b in bad}))
    return 0 if not bad else 1


if __name__ == "__main__":
    raise SystemExit(main())

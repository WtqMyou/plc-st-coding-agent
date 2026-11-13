# -*- coding: utf-8 -*-
"""参考解 × LTL 规约 的有界模型检查验收。

这是**数据质量的第二道闸门**（第一道是测试用例）：
  - 若参考解违反了某条规约，只有两种可能：
      a) 规约写错了 / 写太强（常见：忘了 X 的时序、把"本拍"写成"下拍"）；
      b) 参考解本身有 bug。
    两种都必须当场查清，不能靠"把规约删掉"蒙混过去。
  - 若参考解通过，说明"规约至少对正确实现成立"，反过来就能拿它当裁判
    去判 LLM 生成的代码——这是 P ⊨ φ 能被当判据的前提。

用法：
    python -X utf8 -m stbench.verify_specs              # 全部自建题
    python -X utf8 -m stbench.verify_specs self-hard-02 # 单题
    python -X utf8 -m stbench.verify_specs --json       # 机器可读
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .modelcheck import InputSpace, check as mc_check
from .schema import Problem
from .selfmade_refs import REFS

DATA = Path(__file__).resolve().parent.parent / "datasets" / "selfmade"


def _load(pid: str) -> Problem:
    return Problem.load(DATA / f"{pid}.json")


def _domains(problem: Problem) -> dict[str, list]:
    """复用 driver 的同源推断：从用例里出现过的取值建输入域。"""
    from .st.driver import _collect_domains

    return _collect_domains(problem)


def run_one(pid: str, *, depth: int | None = None) -> dict:
    problem = _load(pid)
    src = REFS[pid]
    ltl_specs = [(s.sid, s.ltl) for s in problem.specs if s.ltl.strip()]
    sim_specs = [(s.sid, s.text) for s in problem.specs if not s.ltl.strip()]

    out: dict = {
        "pid": pid,
        "ltl_total": len(ltl_specs),
        "sim_total": len(sim_specs),
        "states": 0,
        "traces": 0,
        "violations": [],
        "results": [],
        "error": "",
    }
    if not ltl_specs:
        out["error"] = "该题没有可执行 LTL 规约"
        return out

    domains = _domains(problem)
    if not domains:
        out["error"] = "无法从用例推断输入域"
        return out

    rep = mc_check(
        src,
        ltl_specs,
        InputSpace(domains),
        max_depth=depth if depth is not None else problem.mc_max_depth,
        max_traces=problem.mc_max_traces,
        program_name=pid,
    )
    if rep.error:
        out["error"] = rep.error
        return out

    out["states"] = rep.states_explored
    out["traces"] = rep.traces_explored
    for s in rep.specs:
        row = {
            "sid": s.spec_id,
            "formula": s.formula,
            "status": s.status_text(),
            "contradicting": s.contradicting,
            "inconclusive": s.inconclusive,
            "ce_at": s.ce_at,
            "counterexample": s.counterexample[:4],
            "reason": s.reason,
        }
        out["results"].append(row)
        if s.contradicting:
            out["violations"].append(row)
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="参考解 × LTL 规约 有界模型检查")
    ap.add_argument("pids", nargs="*", help="只检查指定 pid")
    ap.add_argument("--json", action="store_true", help="输出 JSON")
    ap.add_argument("--depth", type=int, default=None, help="覆盖搜索深度")
    args = ap.parse_args(argv)

    pids = args.pids or sorted(REFS)
    rows = [run_one(p, depth=args.depth) for p in pids]

    if args.json:
        print(json.dumps(rows, ensure_ascii=False, indent=2))
    else:
        tot_ltl = tot_states = 0
        bad = 0
        print(f"{'题目':<16} {'LTL':>4} {'状态':>6} {'轨迹':>7}  结论")
        print("-" * 74)
        for r in rows:
            if r["error"]:
                print(f"{r['pid']:<16} {r['ltl_total']:>4} {'-':>6} {'-':>7}  ✗ {r['error']}")
                bad += 1
                continue
            tot_ltl += r["ltl_total"]
            tot_states += r["states"]
            ok = not r["violations"]
            mark = "✓ 全部通过" if ok else f"✗ 违反 {len(r['violations'])} 条"
            print(
                f"{r['pid']:<16} {r['ltl_total']:>4} {r['states']:>6} "
                f"{r['traces']:>7}  {mark}"
            )
            if not ok:
                bad += 1
                for v in r["violations"]:
                    print(f"      {v['sid']}: {v['formula']}")
                    print(f"        第 {v['ce_at']} 拍反例: {v['counterexample']}")
            for s in r["results"]:
                if s["inconclusive"]:
                    print(f"      {s['sid']}: 界内无法判定 —— {s['reason']}")
        print("-" * 74)
        print(f"合计 LTL 规约 {tot_ltl} 条，探索状态 {tot_states} 个，"
              f"{'全绿 ✓' if bad == 0 else f'{bad} 道题有问题 ✗'}")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())

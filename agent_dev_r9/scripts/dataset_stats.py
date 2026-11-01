"""生成数据集统计表（Markdown），写进 docs/数据集规范.md §9 或直接贴报告。

用法::

    python -X utf8 scripts/dataset_stats.py
    python -X utf8 scripts/dataset_stats.py --mc      # 额外跑参考解的 LTL（慢）

输出列：题号 / 难度 / 主题 / 用例模式 / 用例数 / 规约数（plcverif+simulation）/
参考解 / MC 结论。MC 一列只有加了 ``--mc`` 才有值，因为跑一次要几分钟。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from stbench.public_refs import REFS, problem_files  # noqa: E402
from stbench.schema import Problem  # noqa: E402


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="数据集统计表")
    ap.add_argument("--mc", action="store_true", help="额外跑有界模型检查（慢）")
    args = ap.parse_args(argv)

    rows = []
    n_cases = n_specs = n_ref = 0
    for f in problem_files():
        p = Problem.load(f)
        src = REFS.get(p.pid)
        has_ref = bool(src)
        n_ref += has_ref
        n_cases += len(p.test_cases)
        n_specs += len(p.specs)
        plc = sum(1 for s in p.specs if (s.verified_by or "") == "plcverif")
        sim = sum(1 for s in p.specs if (s.verified_by or "") == "simulation")
        mc = "—"
        if args.mc and src and p.test_cases:
            from stbench.evaluation import evaluate, verification_status

            r = evaluate(src, p, model_check=True, timeout_s=p.mc_max_seconds+2)
            if r.mc_error:
                mc = f"err:{r.mc_error[:18]}"
            else:
                mc = verification_status(r)+f" {r.mc_specs_hold}/{r.mc_specs_total}" + (
                    f" 违反{r.mc_specs_violated}" if r.mc_specs_violated else ""
                )
        rows.append((p.pid, p.difficulty.value, p.title, p.case_mode,
                     len(p.test_cases), f"{plc}+{sim}", "√" if has_ref else "×", mc))

    print("| 题号 | 难度 | 主题 | 用例模式 | 用例 | 规约(plc+sim) | 参考解 | MC hold |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- |")
    for r in rows:
        print("| `{}` | {} | {} | {} | {} | {} | {} | {} |".format(*r))
    print()
    print(f"合计：{len(rows)} 题，用例 {n_cases} 条，规约 {n_specs} 条，参考解 {n_ref}/{len(rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

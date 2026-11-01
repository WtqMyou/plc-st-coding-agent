"""跑一组对照实验并输出汇总表。

四种实验设置（对应大作业里"消融"要回答的问题）：

| 设置 | 命令 | 回答的问题 |
| --- | --- | --- |
| one-shot | `--max-iters 1` | 没有任何编译反馈时，模型裸能力如何 |
| iterative | `--max-iters 5` | 编译器反馈能把通过率拉高多少 |
| no-ltl    | `--no-ltl`      | 提示词里去掉形式化性质，损失多少 |
| cross-model | 换 `--provider` | 两个基座模型的差异 |

用法::

    # 离线冒烟（不需要任何 key）
    python -X utf8 scripts/run_experiment.py --provider mock --dataset selfmade

    # 真模型
    set DEEPSEEK_API_KEY=sk-xxx
    python -X utf8 scripts/run_experiment.py --provider deepseek:deepseek-chat --max-iters 5
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stbench.harness.runner import Solver, solve_suite, summarize  # noqa: E402
from stbench.providers.base import get_provider  # noqa: E402
from stbench.schema import Problem  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def load_dataset(name: str) -> list[Problem]:
    d = ROOT / "datasets" / name
    if not d.is_dir():
        raise SystemExit(f"数据集不存在：{d}")
    probs = []
    for f in sorted(d.glob("*.json")):
        if f.name.startswith("_"):
            continue
        try:
            probs.append(Problem.load(f))
        except (ValueError, KeyError, TypeError) as e:  # 单题坏了不该拖垮整批实验
            print(f"[warn] 跳过 {f.name}: {e}", file=sys.stderr)
    return probs


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--provider", default="mock", help="如 deepseek:deepseek-chat / anthropic:claude-sonnet-4-5 / mock")
    ap.add_argument("--dataset", default="selfmade", help="datasets/ 下的子目录名")
    ap.add_argument("--max-iters", type=int, default=5, help="最大迭代轮数；1 = one-shot")
    ap.add_argument("--limit", type=int, default=0, help="只跑前 N 题（冒烟用）")
    ap.add_argument("--out", default="", help="汇总结果写到这个 json 路径")
    ap.add_argument("--temperature", type=float, default=0.0)
    ap.add_argument("--no-ltl", action="store_true", help="提示词里去掉形式化性质（消融）")
    ap.add_argument("--mock-script", default="blank",
                    choices=["blank", "echo_reference"],
                    help="mock 通道的回复策略；echo_reference 需要配合 --mock-use-refs")
    ap.add_argument("--mock-use-refs", action="store_true",
                    help="mock 通道按题返回仓库里的参考解（验证 harness 全链路）")
    args = ap.parse_args(argv)

    probs = load_dataset(args.dataset)
    if args.limit:
        probs = probs[: args.limit]
    if not probs:
        raise SystemExit("没有可跑的题目")

    prov = get_provider(args.provider, temperature=args.temperature)
    sys_prompt = None
    if args.no_ltl:
        from stbench.harness.prompts import SYSTEM_PROMPT

        # 消融只改"给不给形式化性质"这一个变量，系统提示词保持不变，
        # 否则两个变量同时变，差异就归因不了。
        sys_prompt = SYSTEM_PROMPT + "\n\n（本次不提供形式化性质列表，请仅依据需求文本实现。）"

    solver = Solver(prov, max_iters=args.max_iters, system_prompt=sys_prompt, include_ltl=not args.no_ltl)
    tag = f"{prov.name}_{prov.model}_{'iter' + str(args.max_iters) if args.max_iters > 1 else 'oneshot'}"
    if args.no_ltl:
        tag += "_noltl"
    log_dir = ROOT / "runs" / tag

    # mock 通道本身不读题，只能靠"按题替换参考解"来模拟一次正确作答；
    # 因此这里按题逐个跑，而不是交给 solve_suite 统管。
    refs = {}
    if args.mock_use_refs:
        from stbench.selfmade_refs import REFS

        refs = dict(REFS)
        # 公共题的参考解按文件维护（datasets/public/tests/*.reference.st），
        # 不并进来就跑不了 --dataset public 的 mock 全链路冒烟。
        from stbench.public_refs import REFS as PUBLIC_REFS

        refs.update(PUBLIC_REFS)

    print(f"数据集 {args.dataset}：{len(probs)} 题 | provider={prov.name} model={prov.model} "
          f"| 设置={solver.setting} max_iters={args.max_iters}")
    if refs:
        from stbench.providers.mock import MockProvider
        from stbench.harness.runner import solve_problem

        records = []
        for p in probs:
            s = Solver(MockProvider(script="echo_reference", reference=refs.get(p.pid, "")),
                       max_iters=args.max_iters)
            records.append(solve_problem(p, s, log_dir=log_dir))
    else:
        records = solve_suite(probs, solver, log_dir=log_dir)

    summary = summarize(records)
    print("\n=== 汇总 ===")
    for k, v in summary.items():
        print(f"  {k:20s} {v}")
    print("\n逐题：")
    for r in records:
        mark = "OK  " if r.solved else "FAIL"
        print(f"  [{mark}] {r.pid:18s} 轮次={len(r.attempts)} "
              f"首轮={(('是' if r.first_try else '否'))} tokens={r.total_tokens}")

    out = Path(args.out) if args.out else log_dir / "summary.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"summary": summary, "records": [r.to_dict() for r in records]},
                              ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n结果已写入 {out}")
    return 0 if summary.get("solve_rate", 0) == 1.0 else 1


if __name__ == "__main__":
    raise SystemExit(main())

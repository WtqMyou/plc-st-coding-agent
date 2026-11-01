"""Offline generation through both real compilers, tests and bounded LTL.

This limited integration smoke is separate from model-performance experiments.
"""
import contextlib
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from stbench.cli import config,problems,reference
from stbench.portability import adapt
from stbench.platforms import CodesysBackend,OpenPLCBackend
from stbench.harness.runner import Solver,solve_problem
from stbench.providers.mock import MockProvider
from stbench.codex_baseline import CodexProvider,ResponsesGateway
from stbench.evaluation import atomic_json


def main():
    cfg=config("");tasks={p.pid:p for p in problems()};rows=[]
    jobs=[("custom","fixture-A","self-easy-02"),("custom","fixture-B","self-medium-03"),
          ("custom","fixture-A","self-hard-02"),("codex","fixture-B","self-medium-03"),
          ("custom","fixture-A","self-hard-05"),("custom","fixture-B","self-hard-06"),
          ("codex","fixture-A","self-hard-07"),("custom","fixture-A","self-medium-05"),
          ("codex","fixture-B","self-medium-06")]
    for framework,model,pid in jobs:
        p=tasks[pid];q,src,_=adapt(p,reference(p),"codesys")
        q.mc_max_seconds=1.5
        with contextlib.ExitStack() as stack:
            if framework=="custom":provider=MockProvider(model=model,reference=src)
            else:
                gateway=stack.enter_context(ResponsesGateway(mock_text=src,model=model))
                provider=CodexProvider(gateway,model=model,mock=True,
                    work_root=Path(cfg["platform_root"])/"builds"/"codex")
            solver=Solver(provider,max_iters=1,model_check=True,mc_seconds=2,task_seconds=600,
                backends=(CodesysBackend(cfg),OpenPLCBackend(cfg)))
            record=solve_problem(q,solver)
        row=dict(label="Offline integration, not model performance",framework=framework,
                 mc_internal_seconds=1.5,mc_hard_seconds=2,**record.to_dict())
        rows.append(row);atomic_json(ROOT/"evidence"/"integration_smoke.json",rows)
        print(framework,pid,record.solved,record.best.verification_status,flush=True)
    return int(not all(r["solved"] and r["attempts"][0]["verification_status"]!="not_run"
        and set(r["attempts"][0]["platform_results"])=={"codesys","openplc"} for r in rows))


if __name__=="__main__":raise SystemExit(main())

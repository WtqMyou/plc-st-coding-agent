"""Rebuild all 15 definitions from generators, keeping canonical ST files separate.

Default is a read-only drift check. --write exports definitions and one full index.
Existing engineering review metadata is preserved; it is not an execution oracle.
"""
import argparse
import json
import runpy
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from stbench.schema import Problem
from stbench.evaluation import atomic_json


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    tasks = []
    for name in ("selfmade_build.py", "selfmade_new5.py"):
        module = runpy.run_path(str(ROOT / "datasets" / name))
        for builder in module["BUILDERS"]:
            p = builder()
            if "attach_cases" in module:p = module["attach_cases"](p)
            path = ROOT / "datasets/selfmade" / (p.pid + ".json")
            old = Problem.load(path)
            for key in ("agent_review", "agent_dev_corrections"):
                if key in old.provenance:p.provenance[key] = old.provenance[key]
            if not args.write and p.to_dict() != old.to_dict():
                raise ValueError("Generator drift: " + p.pid)
            if args.write:p.save(path)
            tasks.append(p)
    index = [dict(pid=p.pid, difficulty=p.difficulty.value, title=p.title, n_vars=len(p.variables),
                  n_specs=len(p.specs), n_cases=len(p.test_cases), n_ltl=sum(bool(s.ltl) for s in p.specs),
                  case_mode=p.case_mode) for p in sorted(tasks, key=lambda p:p.pid)]
    target = ROOT / "datasets/selfmade/_index.json"
    if args.write:atomic_json(target, index)
    elif index != json.loads(target.read_text(encoding="utf-8")):
        raise ValueError("Index drift")
    print("Generators and index agree:", len(tasks), "tasks /", sum(len(p.test_cases) for p in tasks), "cases")


if __name__ == "__main__":main()

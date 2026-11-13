"""Supplementary bounded search of reference programs (independent of run.py's score)."""
import argparse
from collections import Counter
from concurrent.futures import ProcessPoolExecutor, as_completed
import json
from hashlib import sha256
import time
from math import prod
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from stbench.schema import Problem
from stbench.st.driver import StageResult, _attach_model_check, _plain, _collect_domains
from stbench.evaluation import verification_status


def check_one(job):
    path, declared, factor = job
    started = time.monotonic()
    dataset_bytes = path.read_bytes()
    p = Problem.from_dict(json.loads(dataset_bytes))
    if not declared:
        p.mc_max_depth = min(p.mc_max_depth, 5)
        p.mc_max_traces = min(p.mc_max_traces, 2048)
        p.mc_max_seconds = min(p.mc_max_seconds or 4, 4)
    p.mc_max_traces *= factor
    p.mc_max_seconds *= factor
    original = _collect_domains(p)
    source_file=path.parent / "tests" / (p.pid + ".reference.st")
    source_bytes = source_file.read_bytes()
    code = source_bytes.decode("utf8")
    result = StageResult(compiles=True)
    _attach_model_check(code, p, result)
    return dict(pid=p.pid, status=verification_status(result), error=result.mc_error,
                dataset_sha256=sha256(dataset_bytes).hexdigest(),source_sha256=sha256(source_bytes).hexdigest(),
                property_ids=[s.sid for s in p.specs if s.ltl.strip()], properties_checked=result.mc_specs_total,
                properties_hold=result.mc_specs_hold, properties_unresolved=result.mc_specs_inconclusive,
                depth_limit=p.mc_max_depth, transition_limit=p.mc_max_traces, seconds_limit=p.mc_max_seconds,
                explored=result.mc_traces, elapsed_s=round(time.monotonic()-started,3),
                raw_domain_size=prod(map(len,original.values())), input_sizes={k:len(v) for k,v in original.items()},
                details=result.evidence_metadata, violations=_plain(result.mc_violations))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--declared-limits", action="store_true")
    parser.add_argument("--out", type=Path, default=ROOT/"review"/"bounded.json")
    parser.add_argument("--only", nargs="+", help="Restrict optional follow-up to listed task IDs")
    parser.add_argument("--effort", type=int, default=1, help="Multiply time and transition limits, retain depth/domain")
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()
    if args.effort<1 or args.workers<1: parser.error("limits must be positive")
    paths=sorted((ROOT/"datasets").glob("*/*-*.json"))
    if args.only:
        paths=[p for p in paths if p.stem in args.only]
        if {p.stem for p in paths} != set(args.only): parser.error("unknown task ID")
    jobs = [(f,args.declared_limits,args.effort) for f in paths]
    rows=[]
    progress=args.out.with_suffix(".partial.json")
    with ProcessPoolExecutor(max_workers=args.workers) as workers:
        for fut in as_completed([workers.submit(check_one,job) for job in jobs]):
            row=fut.result()
            rows.append(row)
            print(row["pid"],row["status"],row["explored"],row["elapsed_s"],flush=True)
            tmp=progress.with_suffix(".tmp")
            tmp.write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding="utf8")
            tmp.replace(progress)
    rows.sort(key=lambda r:r["pid"])
    summary = Counter(r["status"] for r in rows)
    args.out.write_text(json.dumps(dict(scope="finite reference search",counts=summary,rows=rows),
                                   ensure_ascii=False,indent=2),encoding="utf8")
    progress.unlink(missing_ok=True)
    print(dict(summary))
    for row in rows:
        if row["status"] in {"violated","tool_error"}:
            print(row["pid"],row["error"],[(e["id"],e["at"]) for e in row["violations"]])
    sys.exit(int(any(r["status"] in {"violated","tool_error"} for r in rows)))

"""Offline acceptance of the F1.4 handoff. Run in a freshly extracted release."""
import argparse
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from uuid import uuid4

from stbench.harness.prompts import build_task_prompt
from stbench.parse_bank import parse_problem
from stbench.portability import adapt
from stbench.schema import Problem
from stbench.spec_policy import apply

ROOT = Path(__file__).resolve().parent

def load(path):
    return json.loads(path.read_bytes())

def digest(value):
    return hashlib.sha256(value).hexdigest()

def run(script, *options):
    return subprocess.check_output([sys.executable, "-B", "-X", "utf8", str(ROOT / script),
                                    *map(str, options)], cwd=ROOT)

def check(condition, message):
    if not condition:
        raise ValueError(message)

@contextmanager
def temporary_result():
    folder = ROOT / (".verify-" + uuid4().hex)
    folder.mkdir()
    report = folder / "report.json"
    try:
        yield report
    finally:
        report.unlink(missing_ok=True)
        folder.rmdir()

def verify_contracts():
    bank = load(ROOT / "sources/课程原题.json")
    index = load(ROOT / "sources/index.json")
    prompts = load(ROOT / "agent_inputs.json")
    seen = set()
    public = 0
    for p in sorted(ROOT.glob("datasets/*/*.json")):
        task = Problem.load(p)
        pid = p.stem
        check(task.pid == pid and pid not in seen, pid + " duplicate or wrong ID")
        seen.add(pid)
        prompt = build_task_prompt(task)
        entry = prompts[pid]
        check(prompt == entry["user"] and digest(prompt.encode()) == entry["sha256"], pid + " prompt differs")
        src = (p.parent / "tests" / (pid + ".reference.st")).read_text(encoding="utf-8")
        for platform in ("codesys", "openplc"):
            q, adapted, info = adapt(task, src, platform)
            apply(q)
            check(not info["rules"] and q.to_dict() == task.to_dict() and adapted == src, pid + " overlay")
        if task.source == "public":
            public += 1
            record = index["records"][pid]
            level, i, language = record["json_pointer"].strip("/").split("/")
            raw = bank[level][int(i)][language]
            check(raw == prompt == task.raw_text and digest(raw.encode()) == record["text_sha256"], pid+" course original")
            source_task = parse_problem(raw, pid, "public")
            for field in ("title", "requirements", "variables", "language"):
                check(getattr(task, field) == getattr(source_task, field), pid + " " + field)
        check(task.provenance["source_record"] == "sources/index.json#" + pid, pid + " provenance")
    check(public == 20 and len(seen) == 35 and seen == set(prompts) == set(index["records"]), "wrong task set")
    for name, sha in index["file_sha256"].items():
        check(digest((ROOT / "sources" / name).read_bytes()) == sha, name)
    return public

def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--quick", action="store_true", help="skip supplementary negative controls")
    args = cli.parse_args()
    manifest = load(ROOT / "冻结清单.json")
    for name, sha in manifest["sha256"].items():
        check(digest((ROOT / name).read_bytes()) == sha, "frozen file differs: " + name)
    public = verify_contracts()
    bounds = load(ROOT / "evidence/f14_bounds.json")["rows"]
    check(len(bounds) == len({r["pid"] for r in bounds}) == 35, "incomplete bounds")
    for row in bounds:
        p, = ROOT.glob("datasets/*/" + row["pid"] + ".json")
        ref = p.parent / "tests" / (p.stem + ".reference.st")
        check(row["dataset_sha256"] == digest(p.read_bytes()) and row["source_sha256"] == digest(ref.read_bytes()), p.stem + " stale bounds")
        check(row["status"] in {"bounded_pass","truncated","inconclusive"}, p.stem + " uninvestigated verdict")
    with temporary_result() as destination:
        run("run.py", "--output", destination)
        scores = load(destination)
        check(scores == load(ROOT / "evidence/full_run.json"), "functional score differs")
        run("review/checks/full_traces.py", "--output", destination)
        traces = load(destination)
        check(traces == load(ROOT / "review/trace_audit.json"), "trace verdict differs")
        run("review/checks/render_catalog.py", "--check-frozen")
        for pid in ("public-hard-04", "self-hard-04"):
            run("task.py", pid, "--prompt", "--output", destination)
            check(digest(destination.read_bytes()) == load(ROOT/"agent_inputs.json")[pid]["sha256"], pid+" CLI prompt")
        if not args.quick:
            run("review/f14_public_checks.py", "--output", destination)
            check(load(destination) == load(ROOT/"review/f14_public_checks.json"), "public controls differ")
            run("review/checks/timed_course_cases.py", "--output", destination)
            check(load(destination) == load(ROOT/"evidence/timed_course_cases.json"), "timed controls differ")
            check(json.loads(run("review/checks/release_regressions.py")) == load(ROOT/"evidence/release_regressions.json"), "regressions differ")
            current = json.loads(run("review/f14_self/verify.py"))
            saved = load(ROOT/"review/f14_self/results.json")
            for key in ("gate_reference","fill_reference"):
                saved[key].pop("bounded_search", None)
            check(current == saved, "self-made controls differ")
            check(json.loads(run("review/f14_mean/verify.py")) == load(ROOT/"review/f14_mean/results.json"), "moving-average controls differ")
            check(json.loads(run("review/f14_interlock/verify.py")) == load(ROOT/"review/f14_interlock/results.json"), "interlock / pump / batch controls differ")
    passed = sum(i["passed"] for rows in scores.values() for i in rows)
    total = sum(i["total"] for rows in scores.values() for i in rows)
    print(f'{manifest["version"]} | course originals {public}/20 | tasks 35/35 | functional {passed}/{total} | finite trace/formula {traces["all"]}')
    print(run("platform_review/check.py").decode("utf-8").strip())

if __name__ == "__main__":
    main()

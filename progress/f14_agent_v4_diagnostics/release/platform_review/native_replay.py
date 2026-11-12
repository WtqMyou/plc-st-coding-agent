"""Reproduce the archived offline CODESYS compiler checks and build the separate DINT FIFO."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
from types import SimpleNamespace
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
PROFILE = "CODESYS V3.5 SP22 Patch 4"
INSTALL = Path("E:/PLC_Dev/platforms/CODESYS_3.5.22.40/CODESYS/Common/CODESYS.exe")
TEMPLATE = Path("E:/PLC_Dev/builds/codesys_template.project")
FROZEN_INPUTS = {
    "template": "b9d4f4a48989d80b95f4e3c0587ba8d9643800e2845114c7324926d1c69a07b5",
    "scripts/codesys_build.py": "f6f48fe43e14f621f606fef273f544f8b8148df4bffcdbdac23d7566cd00e540",
    "stbench/platforms.py": "b02372d2173bf38ad2cecd7b1e1ce76a70a94ffb53f41723f0c359b403b122d7",
    "platform_review/peer/native_evidence/positive-control/candidate.st":
        "c71cabca89103cab44de2e30ba6d5fdad0853c459ada2344528c302e461c6cf2",
    "platform_review/peer/native_evidence/negative-control/candidate.st":
        "80fd1cb547c03ba0a01d9500135a14d1f10ead9441eddb58821de0c9ecdc10fb",
    "datasets/public/tests/public-hard-04.reference.st":
        "a4d85014805952e8d28922e9754b48d7a4157e720ca938889c80b9fbbebdd87c",
}
CANDIDATES = {
    "positive-control": "platform_review/peer/native_evidence/positive-control/candidate.st",
    "negative-control": "platform_review/peer/native_evidence/negative-control/candidate.st",
    "course-original": "datasets/public/tests/public-hard-04.reference.st",
    "dint-open-array": "platform_review/portable/public-hard-04.dint-array.st",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def environment(executable, template):
    problems = []
    inputs = {}
    for name, expected in FROZEN_INPUTS.items():
        path = template if name == "template" else ROOT / name
        actual = digest(path) if path.is_file() else None
        inputs[name] = {"path": str(path), "expected_sha256": expected, "actual_sha256": actual}
        if actual != expected:
            problems.append("Missing or different frozen input: " + str(path))
    candidate = ROOT / CANDIDATES["dint-open-array"]
    if not candidate.is_file():
        problems.append("Missing separate DINT candidate: " + str(candidate))
    if os.name != "nt":
        problems.append("Windows host required by the frozen target")
    if not executable.is_file():
        problems.append("Missing CODESYS compiler: " + str(executable))
    elif executable.stat().st_size != 526592:
        problems.append("CODESYS executable size differs from the recorded 526592 bytes")
    return {"ready": not problems, "profile": PROFILE, "target": "CODESYS Control Win x64",
            "executable": str(executable), "exe_sha256_this_host": digest(executable) if executable.is_file() else None,
            "executable_archived_sha256": None, "frozen_inputs": inputs,
            "dint_source_bytes_sha256": digest(candidate) if candidate.is_file() else None,
            "problems": problems}


def matches_expectation(name, result):
    if result.returncode != 0 or not result.artifact_dir:
        return False
    log = "\n".join(result.diagnostics).lower()
    if name == "negative-control":
        return result.status == "failed" and "expression expected" in log
    if name == "course-original":
        return (result.status == "failed" and "unknown type: 'variant'" in log
                and "only supported for arrays" in log and "cannot apply indexing" in log)
    boot = Path(result.artifact_dir) / "candidate.app"
    return result.status == "passed" and boot.is_file() and boot.stat().st_size > 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", type=Path, default=INSTALL, help="path to the SP22 Patch 4 CODESYS.exe")
    parser.add_argument("--template", type=Path, default=TEMPLATE, help="frozen Control Win x64 .project")
    parser.add_argument("--output", "--output-dir", type=Path, default=Path("native_replay_runs"),
                        help="parent for unique run directories, raw codegen outputs and compiler messages")
    parser.add_argument("--check-env", action="store_true", help="inspect inputs without launching a compiler")
    args = parser.parse_args()
    executable, template = args.executable.resolve(), args.template.resolve()
    state = environment(executable, template)
    if args.check_env or not state["ready"]:
        print(json.dumps(state, ensure_ascii=False, indent=2))
        return 0 if state["ready"] else 2

    sys.path.insert(0, str(ROOT))
    from stbench.evaluation import atomic_json
    from stbench.platforms import CodesysBackend

    run_dir = args.output.resolve() / ("codesys-" + uuid4().hex)
    run_dir.mkdir(parents=True, exist_ok=False)
    (run_dir / "cache").mkdir()
    backend = CodesysBackend({"codesys_executable": str(executable), "codesys_template": str(template),
                              "codesys_profile": PROFILE, "platform_root": str(run_dir)})
    summary = {"environment": state, "compile_only": True, "artifact_directory": str(run_dir),
               "all_expectations_met": False, "checks": {}}
    for name, relative in CANDIDATES.items():
        if name == "course-original" and not all(summary["checks"][c]["matched_expectation"]
                                                  for c in ("positive-control", "negative-control")):
            summary["stop_reason"] = "Compiler controls did not reproduce. FIFO builds skipped."
            break
        path = ROOT / relative
        result = backend.compile(path.read_text(encoding="utf-8"), SimpleNamespace(pid=name))
        summary["checks"][name] = {"file": relative, "file_bytes_sha256": digest(path),
                                   "matched_expectation": matches_expectation(name, result),
                                   "build": result.to_dict()}
        atomic_json(run_dir / "summary.json", summary)
    summary["all_expectations_met"] = (len(summary["checks"]) == len(CANDIDATES)
                                       and all(c["matched_expectation"] for c in summary["checks"].values()))
    atomic_json(run_dir / "summary.json", summary)
    for name, item in summary["checks"].items():
        print(f"{name}: compiler={item['build']['status']}; matched={item['matched_expectation']}")
    print(run_dir / "summary.json")
    return 0 if summary["all_expectations_met"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

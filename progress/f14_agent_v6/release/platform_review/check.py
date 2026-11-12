"""Check archived CODESYS evidence and replay both local FIFO profiles."""
from hashlib import sha256
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

def check(condition, message):
    if not condition:
        raise ValueError(message)

def load(path):
    return json.loads(path.read_bytes())

def digest(path):
    return sha256(path.read_bytes()).hexdigest()

def main():
    upstream = load(HERE / "F1.4原冻结清单.json")["sha256"]
    for name, value in upstream.items():
        if name.startswith(("datasets/", "sources/")) or name == "agent_inputs.json":
            check(digest(ROOT / name) == value, "course release changed: " + name)
    peer = HERE / "peer"
    files = load(peer / "delivery_manifest.json")["files"]
    for path in peer.rglob("*"):
        if path.is_file() and path != peer / "delivery_manifest.json":
            check(files[path.relative_to(peer).as_posix()] == digest(path), str(path))

    statuses = {"positive-control":"passed", "negative-control":"failed", "public-easy-04":"passed",
                "public-medium-02":"passed", "public-hard-04":"failed"}
    for pid, expected in statuses.items():
        folder = peer / "native_evidence" / pid
        result, native = load(folder / "result.json"), load(folder / "codesys_result.json")
        candidate = folder / "candidate.st"
        check(result["status"] == native["status"] == expected and result["diagnostics"] == native["diagnostics"], pid)
        check(result["source_sha256"] == sha256(candidate.read_text(encoding="utf-8").encode()).hexdigest(), pid + " source")
        if pid.startswith("public"):
            check(candidate.read_bytes() == (ROOT/"datasets/public/tests"/(pid + ".reference.st")).read_bytes(), pid + " reference")
        if pid == "public-hard-04":
            check(any("10 errors, 0 warnings" in s for s in native["diagnostics"]), "missing build result")
            check(any("Unknown type: 'VARIANT'" in s for s in native["diagnostics"]), "missing VARIANT diagnosis")

    jobs = (("original/verify_original_bindings.py", "--root", "original/results.json"),
            ("portable/verify_bindings.py", "--release", "portable/binding_results.json"))
    for script, flag, archived in jobs:
        output = subprocess.check_output([sys.executable, "-B", "-X", "utf8", str(HERE / script), flag, str(ROOT)], cwd=ROOT)
        check(json.loads(output) == load(HERE / archived), script + " replay differs")
    print("P1 | archived CODESYS: 2 passed, 1 failed; 2 controls as expected | local FIFO binding reports reproduced")

if __name__ == "__main__":
    main()

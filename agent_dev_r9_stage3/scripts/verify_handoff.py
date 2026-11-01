"""Verify archive hashes and run regression tests from a clean E: extraction."""
import argparse
import hashlib
import json
import subprocess
import sys
import time
import uuid
import zipfile
from pathlib import Path


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("package",type=Path)
    args=ap.parse_args()
    package=args.package.resolve()
    destination=Path("E:/PLC_Dev/builds/handoff_validation")/uuid.uuid4().hex
    destination.mkdir(parents=True)
    with zipfile.ZipFile(package) as archive:
        for name in archive.namelist():
            path=(destination/name).resolve()
            if destination.resolve() not in path.parents:raise ValueError("Unsafe archive member")
        archive.extractall(destination)
    root=destination/"agent_dev"
    current=destination/"MANIFEST_continuation.json"
    manifest_path=current if current.is_file() else root/"MANIFEST_v2.json"
    manifest_root=destination if current.is_file() else root
    manifest=json.loads(manifest_path.read_text(encoding="utf-8"))
    for item in manifest["files"]:
        member=(manifest_root/item["path"]).resolve()
        if manifest_root.resolve() not in member.parents:raise ValueError("Unsafe manifest member")
        content=member.read_bytes()
        if len(content)!=item["bytes"] or hashlib.sha256(content).hexdigest()!=item["sha256"]:
            raise ValueError("Manifest mismatch: "+item["path"])
    result=subprocess.run([sys.executable,"-B","-X","utf8","-m","unittest","discover",
        "-s","tests","-p","test_v2*.py","-q"],cwd=root,capture_output=True,
        encoding="utf-8",errors="replace",timeout=120)
    gate=subprocess.run([sys.executable,"-B","-X","utf8","-m","stbench","matrix",
        "--out",str(destination/"unauthorized_live"/"summary.json")],cwd=root,capture_output=True,
        encoding="utf-8",errors="replace",timeout=20)
    report=dict(package=str(package),sha256=hashlib.sha256(package.read_bytes()).hexdigest(),
        manifest_files=len(manifest["files"]),extracted_to=str(root),
        regression_exit=result.returncode,regression_output=result.stdout+result.stderr,
        unpaid_gate_passed=gate.returncode==2 and "Live calls are disabled" in gate.stderr,
        verified_at=time.strftime("%Y-%m-%dT%H:%M:%S"))
    out=package.with_suffix(".qa.json")
    with out.open('x',encoding='utf-8') as target:
        target.write(json.dumps(report,ensure_ascii=False,indent=2))
    print(json.dumps(report,ensure_ascii=False,indent=2))
    return int(result.returncode!=0 or not report["unpaid_gate_passed"])


if __name__=="__main__":raise SystemExit(main())

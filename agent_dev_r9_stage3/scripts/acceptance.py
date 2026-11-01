"""Offline acceptance; writes actual command output and fails on any failed check."""
import json
import subprocess
import sys
import time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from stbench.evaluation import atomic_json

def main():
    rows=[]
    commands=[
        ["-m","unittest","discover","-s","tests","-p","test_v2*.py","-v"],
        ["tests/test_verifier.py"],
        ["tests/test_harness.py"],
        ["-m","stbench","verify-refs","--out","evidence/reference_tests.json"],
        ["scripts/check_dataset.py"],
        ["scripts/check_dataset.py","--selfmade"],
    ]
    logs=ROOT/"evidence"/"acceptance"
    logs.mkdir(parents=True,exist_ok=True)
    for i,args in enumerate(commands,1):
        t=time.monotonic()
        result=subprocess.run([sys.executable,"-B","-X","utf8"]+args,cwd=ROOT,
             capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=600)
        name=f"{i:02d}.log"
        (logs/name).write_text(result.stdout+"\n"+result.stderr,encoding="utf-8")
        row=dict(command=args,returncode=result.returncode,seconds=time.monotonic()-t,log=name)
        rows.append(row);atomic_json(logs/"results.json",rows)
        print("PASS" if result.returncode==0 else "FAIL",args,flush=True)
    return int(any(r["returncode"] for r in rows))
if __name__=="__main__":
    raise SystemExit(main())

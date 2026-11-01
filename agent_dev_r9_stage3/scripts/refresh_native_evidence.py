"""Reuse exact-source native results and recompile changed artifacts."""
import argparse
import hashlib
import json
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from stbench.cli import config,problems,reference,export_summary
from stbench.platforms import CodesysBackend,OpenPLCBackend
from stbench.portability import adapt
from stbench.evaluation import atomic_json,local_tests

ap=argparse.ArgumentParser()
ap.add_argument("--platform",choices=["codesys","openplc"],required=True)
ap.add_argument("--config",default="")
ap.add_argument("--adapted",action="store_true")
args=ap.parse_args()
cfg=config(args.config)
b=(CodesysBackend if args.platform=="codesys" else OpenPLCBackend)(cfg)
tag=args.platform+("_adapted" if args.adapted else "_original")
out=ROOT/"evidence"/(tag+".json")
old=json.loads(out.read_text(encoding="utf-8")) if out.is_file() else []
# A separate retry record is accepted only after the exact-source check below.
retry=ROOT/"evidence"/(tag+"_hard02_retry.json")
if retry.is_file():
    old+=json.loads(retry.read_text(encoding="utf-8"))
index={r["pid"]:r for r in old}
other=ROOT/"evidence"/(args.platform+("_original" if args.adapted else "_adapted")+".json")
shared={r["pid"]:r for r in json.loads(other.read_text(encoding="utf-8"))} if other.is_file() else {}
rows=[]
for p in problems():
    src=reference(p);q=p;mapping=None
    if args.adapted:q,src,mapping=adapt(p,src,args.platform)
    source_hash=hashlib.sha256(src.encode()).hexdigest()
    candidates=[index.get(p.pid),shared.get(p.pid)]
    prior=next((r for r in candidates if r and r["status"] in ("passed","failed")
        and r["source_sha256"]==source_hash and r.get("platform_identity")==b.identity()),None)
    if prior:
        row=dict(prior)
    else:
        row=dict(pid=p.pid,adaptation=mapping,**b.compile(src,q).to_dict())
    tests=local_tests(src,q)
    row.update(local_tests_passed=tests.tests_passed,local_tests_total=tests.tests_total,
               local_static_compiles=tests.compiles,adaptation=mapping)
    rows.append(row);atomic_json(out,rows)
    print(tag,p.pid,row["status"],flush=True)
export_summary(out,rows)
raise SystemExit(int(any(r["status"]!="passed" for r in rows)))

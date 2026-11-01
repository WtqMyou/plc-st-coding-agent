"""Fast real reference compilation; per-job watchdog, hashes and fresh nonces.

This audit optimization is not used for model timing comparisons.
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from stbench.cli import config,problems,reference,export_summary
from stbench.platforms import CodesysBackend,CompileResult,split_st
from stbench.portability import adapt
from stbench.evaluation import atomic_json,local_tests


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--adapted",action="store_true")
    args=ap.parse_args()
    cfg=config("");backend=CodesysBackend(cfg);identity=backend.identity()
    out=ROOT/"evidence"/("codesys_adapted.json" if args.adapted else "codesys_original.json")
    old=[]
    for path in (out,ROOT/"evidence"/("codesys_original.json" if args.adapted else "codesys_adapted.json")):
        if path.is_file():old.extend(json.loads(path.read_text(encoding="utf-8")))
    batch=Path(cfg["platform_root"])/"builds"/"codesys"/("batch_"+uuid.uuid4().hex[:10])
    batch.mkdir(parents=True)
    rows=[];jobs=[]
    for p in problems():
        src=reference(p);q=p;mapping=None
        if args.adapted:q,src,mapping=adapt(p,src,"codesys")
        digest=hashlib.sha256(src.encode()).hexdigest()
        prior=next((r for r in old if r["pid"]==p.pid and r["source_sha256"]==digest
            and r["platform_identity"]==identity and r["status"] in ("passed","failed")),None)
        if prior:row=dict(prior)
        else:
            work=batch/p.pid;work.mkdir()
            (work/"candidate.st").write_text(src,encoding="utf-8")
            nonce=uuid.uuid4().hex
            job=split_st(src)|dict(template=cfg["codesys_template"],project=str(work/"candidate.project"),
                result=str(work/"codesys_result.json"),nonce=nonce)
            atomic_json(work/"job.json",job)
            row=dict(pid=p.pid,**CompileResult("codesys","not_run",artifact_dir=str(work),
                source_sha256=digest,platform_identity=identity).to_dict())
            jobs.append(dict(path=str(work/"job.json"),result=job["result"],nonce=nonce,row=row))
        r=local_tests(src,q)
        row.update(adaptation=mapping,local_static_compiles=r.compiles,
            local_tests_passed=r.tests_passed,local_tests_total=r.tests_total)
        rows.append(row)
    if jobs:
        runner=batch/"runner.py"
        shutil.copyfile(ROOT/"scripts"/"codesys_batch_runner.py",runner)
        heartbeat=batch/"heartbeat.json"
        atomic_json(batch/"batch.json",dict(driver=str(ROOT/"scripts"/"codesys_build.py"),
            heartbeat=str(heartbeat),jobs=[{k:v for k,v in j.items() if k!="row"} for j in jobs]))
        values=[cfg["codesys_executable"],cfg["codesys_profile"],str(runner),str(batch/"batch.json")]
        if any('"' in v or "\n" in v for v in values):raise ValueError("Invalid CODESYS command path")
        command='"'+values[0]+'" --noUI --culture=en-US --profile="'+values[1]+'" --runscript="'+values[2]+'" --scriptargs:"'+values[3]+'"'
        started=time.monotonic();last_nonce=None;job_started=started;timed_out=None
        with (batch/"stdout.log").open("wb") as stdout,(batch/"stderr.log").open("wb") as stderr:
            process=subprocess.Popen(command,stdout=stdout,stderr=stderr,
                env=dict(os.environ,TEMP=str(backend.root/"cache"),TMP=str(backend.root/"cache")))
            while process.poll() is None:
                try:
                    current=json.loads(heartbeat.read_text(encoding="utf-8"))
                    if current["nonce"]!=last_nonce:last_nonce=current["nonce"];job_started=time.monotonic()
                except (OSError,ValueError,KeyError):pass
                if time.monotonic()-job_started>backend.timeout:
                    timed_out=last_nonce or jobs[0]["nonce"]
                    subprocess.run(["taskkill","/PID",str(process.pid),"/T","/F"],capture_output=True)
                    process.wait(timeout=15);break
                time.sleep(.5)
        for item in jobs:
            row=item["row"];row["returncode"]=process.returncode
            path=Path(item["result"])
            if path.is_file():
                report=json.loads(path.read_text(encoding="utf-8"))
                if report.get("nonce")!=item["nonce"]:raise ValueError("Batch nonce mismatch")
                row.update(status=report["status"],diagnostics=report.get("diagnostics",[]),elapsed_s=report.get("elapsed_s",0))
            else:
                row.update(status="timeout" if item["nonce"]==timed_out else "tool_error",
                           diagnostics=["No completed report; see shared batch process logs"])
            row["shared_process_log"]=str(batch/"stdout.log")
            atomic_json(Path(row["artifact_dir"])/"result.json",row)
            print(row["pid"],row["status"],flush=True)
        atomic_json(batch/"batch_process.json",dict(returncode=process.returncode,
            wall_seconds=time.monotonic()-started,timed_out_nonce=timed_out,jobs=len(jobs)))
    export_summary(out,rows)
    print("Native results:",sum(r["status"]=="passed" for r in rows),"/",len(rows))
    return int(any(r["status"]!="passed" for r in rows))


if __name__=="__main__":raise SystemExit(main())

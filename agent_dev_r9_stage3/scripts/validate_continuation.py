"""Versioned offline acceptance; historical evidence is never overwritten."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from stbench.campaign import digest
from stbench.evaluation import atomic_json


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    commands=[
        ['-m','unittest','discover','-s','tests','-p','test_v2*.py','-v'],
        ['tests/test_verifier.py'],['tests/test_harness.py'],
        ['-m','stbench','verify-refs','--out',str(out/'reference_tests.json')],
        ['scripts/check_dataset.py'],['scripts/check_dataset.py','--selfmade'],
        ['scripts/offline_transport_smoke.py','--out',str(out/'transport_smoke.json')],
    ]
    before=digest();rows=[]
    for i,command in enumerate(commands,1):
        start=time.monotonic()
        p=subprocess.run([sys.executable,'-B','-X','utf8']+command,cwd=ROOT,
            capture_output=True,encoding='utf-8',errors='replace',timeout=600)
        log=out/f'{i:02}.log';log.write_text(p.stdout+'\n'+p.stderr,encoding='utf-8')
        rows.append(dict(command=command,returncode=p.returncode,seconds=time.monotonic()-start,
            log=log.name,log_sha256=hashlib.sha256(log.read_bytes()).hexdigest()))
        atomic_json(out/'results.json',rows)
        print('PASS' if p.returncode==0 else 'FAIL',command,flush=True)
    tests=(out/'01.log').read_text(encoding='utf-8')
    required={
        'cli_tree_deadline':'test_cli_tree_deadline_keeps_logs_without_inherited_pipe_wait',
        'upstream_failure_aborts_cli':'test_upstream_failure_aborts_actual_cli_without_a_second_request',
        'single_upstream_request':'test_upstream_failure_aborts_actual_cli_without_a_second_request',
        'full_request_window':'test_thirteen_seconds_remaining_never_creates_a_request_or_charge',
        'request_window_keeps_best':'test_observed_latency_sequence_stops_before_a_short_paid_request',
        'genuine_timeout_keeps_halt':'test_a_genuine_upstream_timeout_keeps_the_unknown_reservation_and_halt',
    }
    passed=all(r['returncode']==0 for r in rows) and before==digest()
    checks={k:any(v in line and line.endswith(' ... ok') for line in tests.splitlines()) for k,v in required.items()}
    proof=dict(passed=passed and all(checks.values()),source_sha256=before,request_seconds=420,cli_seconds=450,request_window_seconds=450,
        deadline_checks=checks,checks=rows,warning='Offline acceptance; no vendor model calls')
    atomic_json(out/'validation.json',proof)
    return int(not proof['passed'])


if __name__=='__main__':raise SystemExit(main())

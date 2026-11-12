"""Offline timing, dialect and judge calibration audit; no paid model calls."""
from pathlib import Path
import collections
import json
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import f14_v2_study as base
ROOT=base.REPO/'progress/evidence/f14_v3_preflight_20261112'

def main():
    ledger=Path(base.config()['budget_ledger_path']);before=ledger.read_bytes()
    old=Path('E:/PLC_Dev/evidence/real_experiments/f14_p1_20261111b')
    records=[base.load(p) for p in (old/'jobs').glob('*/*.json') if p.name.count('.')==1]
    attempts=[a for r in records for a in r['attempts']]
    http=[base.load(p) for p in (old/'transport_private').rglob('diagnostic.json')]
    natives=[a.get('judge',{}).get('platform_results',{}).get('codesys',{}) for a in attempts]
    stats=dict(jobs=len(records),requests=len(attempts),job_seconds=sum(r['wall_seconds'] for r in records),
        old_latency_includes_judge_seconds=sum(a.get('latency_s',0) for a in attempts),
        http_seconds=sum(d.get('elapsed_s',0) for d in http),http_records=len(http),
        native_compile_seconds=sum(n.get('elapsed_s',0) for n in natives),native_compiles=sum(bool(n.get('artifact_dir')) for n in natives),
        empty_or_incomplete=sum(r['stop_reason']=='generation_incomplete' for r in records),
        incomplete_responses_do_not_auto_retry=True,critical_path_claim='HTTP and native work overlap under parallel scheduling; sum latency is not HTTP time')
    base.atomic_json(ROOT/'timing_audit.json',stats)
    sys.path.insert(0,str(base.REPO/'progress/f14_agent_v3'))
    from formatting import normalize
    rows=[]
    for pid,task in base.tasks().items():
        path,=base.RELEASE.glob('datasets/*/tests/'+pid+'.reference.st');source=path.read_text(encoding='utf-8')
        formatted,edits=normalize(source)
        # Use an isolated worker; importing the transport runtime must not select its older judge.
        import subprocess
        request=dict(source=formatted,pid=pid,mode='functional')
        p=subprocess.run([sys.executable,'-B','-X','utf8',str(base.REPO/'progress/f14_agent_v3/judge_worker.py')],input=json.dumps(request),capture_output=True,text=True,encoding='utf-8',timeout=30)
        assert p.returncode==0,p.stderr
        result=json.loads(p.stdout)['result'];assert result['tests_passed']==result['tests_total']==len(task['test_cases']),(pid,result)
        rows.append(dict(pid=pid,tests_passed=result['tests_passed'],semicolon_insertions=len(edits),raw_sha256=base.sha(path)))
    assert len(rows)==35 and sum(r['tests_passed'] for r in rows)==946 and ledger.read_bytes()==before
    base.atomic_json(ROOT/'semicolon_reference_replay.json',dict(tasks=35,passed=946,rows=rows,model_requests=0,original_reference_files_unchanged=True))
    print('PASS timing audit and semicolon-only 35/35 reference replay, 946 cases; ledger unchanged',flush=True)

if __name__=='__main__':main()

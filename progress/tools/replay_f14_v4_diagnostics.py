"""Free, separate tool-correction replay. No official answer, fee or score is overwritten."""
from concurrent.futures import ThreadPoolExecutor,as_completed
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time
import f14_v3_core as s

V4=s.REPO/'progress/f14_agent_v4_diagnostics'
ROOT=Path('E:/PLC_Dev/evidence/offline_replays/f14_v4_20261112')
MIRROR=s.REPO/'progress/evidence/f14_v4_diagnostics_20261112'
ORIGINAL=Path(s.config()['campaign_root'])
NATIVE=threading.Lock();FORMAL=threading.Semaphore(2)
spec=importlib.util.spec_from_file_location('v4_safe_formatting',V4/'formatting.py')
fmt=importlib.util.module_from_spec(spec);spec.loader.exec_module(fmt)

def worker(code,pid,mode,version=4):
    path=V4/'judge_worker.py' if version==4 else s.WORKER
    env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1',PYTHONUTF8='1')
    for key in ('DMXAPI_API_KEY','F14_DMXAPI_SECONDARY_KEY','OPENAI_API_KEY'):env.pop(key,None)
    p=subprocess.run([sys.executable,'-B','-X','utf8',str(path)],input=json.dumps(dict(source=code,pid=pid,mode=mode,seconds=30)),
        capture_output=True,text=True,encoding='utf-8',env=env,timeout=40 if mode=='bounded' else 30)
    assert p.returncode==0,p.stderr
    return json.loads(p.stdout)

def attempt(job,old):
    result=copy.deepcopy(old);result['diagnostic_only']=True
    if not old.get('code'):return dict(normalization_only=copy.deepcopy(result),full=result)
    folder=ORIGINAL/'jobs'/job['condition'];raw=(folder/(job['pid']+f".raw_candidate_{old['idx']+1:02}.st")).read_bytes().decode()
    code,edits=fmt.normalize(raw);native=copy.deepcopy(old.get('judge',{}).get('platform_results',{}).get('codesys',{}))
    changed=code!=old['code']
    if changed:
        with NATIVE:
            backend=s.old.old.support.CodesysBackend(s.config())
            native=backend.compile(code,type('P',(),dict(pid='diag_v4_'+job['pid']))()).to_dict()
        assert native['status'] in ('passed','failed'),native
        target=ROOT/'corrected_candidates'/job['condition']/(job['pid']+f".{old['idx']}.st")
        target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(code.encode())
    if native.get('status') not in ('passed','unsupported_platform'):
        return dict(normalization_only=copy.deepcopy(result),full=result,source_changed=changed,native=native)
    static=worker(code,job['pid'],'static')
    if not static['result']['compiles']:
        return dict(normalization_only=copy.deepcopy(result),full=result,source_changed=changed,native=native,unresolved_errors=static['result']['compile_errors'])
    functional=worker(code,job['pid'],'functional')
    only=worker(code,job['pid'],'functional',3) if changed else None
    complete=functional['result']['compiles'] and functional['result']['tests_passed']==functional['result']['tests_total']
    formal_reused=False
    if complete:
        if not changed and old['functional_pass']:
            functional=copy.deepcopy(functional);functional['verification_status']=old['verification_status'];formal_reused=True
            functional['result']['model_check']=copy.deepcopy(old['judge']['model_check'])
            functional['result']['evidence_metadata']['formal_evidence_reused_from_unchanged_candidate']=old['code_hash']
        else:
            with FORMAL:functional=worker(code,job['pid'],'bounded')
    functional['result']['platform_results']={'codesys':native}
    full=s.classify(functional)
    full.update(idx=old['idx'],code=code,code_hash=hashlib.sha256(code.encode()).hexdigest(),diagnostic_only=True,format_edits=edits,
        original_candidate_sha256=old['code_hash'],source_changed=changed,formal_status_reused=formal_reused)
    normalization_only=copy.deepcopy(old)
    if only is not None:
        only['result']['platform_results']={'codesys':native}
        normalization_only=s.classify(only);normalization_only.update(idx=old['idx'],code=code,code_hash=hashlib.sha256(code.encode()).hexdigest(),diagnostic_only=True)
    assert not old['functional_pass'] or full['functional_pass'],('Lost original functional pass',job['job_id'],old['idx'])
    return dict(normalization_only=normalization_only,full=full,source_changed=changed,native=native)

def main():
    assert not ROOT.exists(),'Preserve diagnostic evidence; use a new version for another replay'
    ROOT.mkdir(parents=True);MIRROR.mkdir(parents=True)
    cfg=s.config();ledger=Path(cfg['budget_ledger_path']);before=ledger.read_bytes();plan=s.load(ORIGINAL/'study_plan.json')
    assert s.old.old.support.CodesysBackend(cfg).identity()==plan['native_identity']
    rawrecords={j['job_id']:s.load(ORIGINAL/'jobs'/j['condition']/(j['pid']+'.json')) for j in plan['jobs']}
    hashes={key:hashlib.sha256(json.dumps(value,ensure_ascii=False).encode()).hexdigest() for key,value in rawrecords.items()}
    tasks=[(job,a) for job in plan['jobs'] for a in rawrecords[job['job_id']]['attempts']]
    results={};started=time.monotonic()
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures={pool.submit(attempt,j,a):(j['job_id'],a['idx']) for j,a in tasks}
        for future in as_completed(futures):
            key,index=futures[future];result=future.result();results[(key,index)]=result
            condition,pid=key.split('/');path=ROOT/'attempts'/condition/(pid+f'.{index}.json');s.atomic_json(path,result)
            if len(results)%20==0:print('FREE REPLAY',len(results),'/',len(tasks),flush=True)
    rows=[]
    for job in plan['jobs']:
        raw=rawrecords[job['job_id']];per=[results[(job['job_id'],a['idx'])] for a in raw['attempts']]
        versions={version:[v[version] for v in per] for version in ('normalization_only','full')}
        row=dict(job_id=job['job_id'],condition=job['condition'],pid=job['pid'],tests_total=raw['tests_total'],original_best=raw['attempts'][raw['best_attempt']])
        for name,values in versions.items():
            best=s.select_best(values);row[name]=values[best]
        rows.append(row)
    assert len(rows)==140 and len(results)==230 and ledger.read_bytes()==before
    for key,oldhash in hashes.items():
        condition,pid=key.split('/');current=s.load(ORIGINAL/'jobs'/condition/(pid+'.json'))
        assert hashlib.sha256(json.dumps(current,ensure_ascii=False).encode()).hexdigest()==oldhash
    data=dict(diagnostic_only=True,not_new_model_experiment=True,model_calls=0,official_results_unchanged=True,
        original_ledger_sha256=hashlib.sha256(before).hexdigest(),seconds=round(time.monotonic()-started,3),rows=rows)
    s.atomic_json(ROOT/'diagnostic_results.json',data);s.atomic_json(MIRROR/'diagnostic_results.json',data)
    totals={name:sum(bool(row[name]['functional_pass']) for row in rows) for name in ('original_best','normalization_only','full')}
    s.atomic_json(MIRROR/'completion.json',dict(passed=True,jobs=140,attempts=230,new_model_calls=0,totals=totals,ledger_unchanged=True,original_records_unchanged=True))
    print('PASS free replay',totals,flush=True)

if __name__=='__main__':main()

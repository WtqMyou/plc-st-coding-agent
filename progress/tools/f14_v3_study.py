"""Bounded parallel full study; individual budget views and a single publisher."""
import argparse
from concurrent.futures import ThreadPoolExecutor,wait,FIRST_COMPLETED
import ctypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import f14_v3_core as s
from f14_v3_budget import Coordinator,authorize,BASELINE,HISTORY,TOTAL,KIND
from f14_v3_report import report,serve

def publish():
    assert not subprocess.check_output(['git','diff','--cached','--name-only'],cwd=s.REPO)
    subprocess.run(['git','add','--',s.MIRROR.relative_to(s.REPO).as_posix()],cwd=s.REPO,check=True,capture_output=True)
    if subprocess.run(['git','diff','--cached','--quiet'],cwd=s.REPO).returncode:
        subprocess.run(['git','commit','-q','-m','chore: archive parallel Agent study progress'],cwd=s.REPO,check=True,capture_output=True)
    env=dict(os.environ,GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='never')
    error=None
    for attempt in range(3):
        try:
            subprocess.run(['git','-c','http.version=HTTP/1.1','-c','http.sslBackend=openssl','push','origin','main'],cwd=s.REPO,env=env,check=True,capture_output=True,timeout=40)
            return
        except (subprocess.CalledProcessError,subprocess.TimeoutExpired) as exc:
            error=type(exc).__name__
            if attempt<2:time.sleep(attempt+1)
    # Git retry is independent from model requests; retain local evidence and retry at the next publication.
    s.atomic_json(Path(s.config()['campaign_root'])/'sync_pending.json',dict(error=error,at=s.stamp(),paid_requests_retried=False))

def prepare(cfg):
    root=Path(cfg['campaign_root']);assert root.is_dir() and not (root/'prepared.json').exists()
    before=Path(cfg['budget_ledger_path']).read_bytes();ledger=json.loads(before)
    assert ledger['spent_cny']==BASELINE and len(ledger['events'])==HISTORY and ledger['limit_cny']==190
    log=root/'free_tests.log'
    with log.open('xb') as output:
        p=subprocess.run([sys.executable,'-B','-X','utf8','-m','unittest','discover','-s','progress/tests','-p','test_f14_v3.py','-v'],cwd=s.REPO,stdout=output,stderr=output,timeout=300)
    assert p.returncode==0,log.read_text(encoding='utf-8')[-3000:]
    assert Path(cfg['budget_ledger_path']).read_bytes()==before
    (root/'ledger_before_study.json').write_bytes(before)
    proof=dict(approved_cap_cny=210,original_user_answers=['提高到210元，修复验收后直接启动','累计上限提高到210元，运行完整140题次'],
        old_batch='f14_v2_public_20261112b',old_request_id=ledger['events'][-1]['request_id'],old_timeout_reservation_retained=ledger['events'][-1]['reserved_cny'],
        initial_accounted_cny=BASELINE,initial_events=HISTORY,not_retrying_old_request=True,new_independent_batch=True,
        ledger_before_sha256=s.sha(root/'ledger_before_study.json'))
    s.atomic_json(root/'authorization_proof.json',proof)
    plan=s.build_plan(cfg,ledger)
    plan.update(concurrency=cfg['concurrency'],authorization_proof_sha256=s.sha(root/'authorization_proof.json'))
    s.atomic_json(root/'study_plan.json',plan)
    s.atomic_json(root/'validation.json',dict(passed=True,tests=log.read_text(encoding='utf-8'),local_routes=140,external_model_calls=0,
        reference_cases=946,negative_controls=35,private_rename_cases=946,normalization='terminator semicolons only',budget_unchanged=True))
    s.atomic_json(root/'prepared.json',dict(plan_sha256=s.sha(root/'study_plan.json'),validation_sha256=s.sha(root/'validation.json')))
    s.atomic_json(root/'study_state.json',dict(state='prepared',at=s.stamp()))
    report(cfg,plan)
    print('PREPARED 140 independent jobs; new worst reserve',plan['worst_reservation_cny'],'total',float(s.money(BASELINE)+s.money(plan['worst_reservation_cny'])),flush=True)

def coordinator(cfg,plan):
    root=Path(cfg['campaign_root'])
    return Coordinator(cfg['budget_ledger_path'],dict(plan,sha256=s.sha(root/'study_plan.json'),ledger_before=str(root/'ledger_before_study.json')))

def live(cfg,resume=False):
    root=Path(cfg['campaign_root']);plan=s.verify(cfg)
    s.old.old.support.no_other_runner(cfg)
    assert cfg['user_authorized_total_cap_cny']==210
    s.old.ensure_pushed();binding=s.credentials.load_credentials(cfg);catalog=s.credentials.catalog(cfg,'secondary')
    assert s.sha(root/'authorization_proof.json')==plan['authorization_proof_sha256']
    if not resume:
        assert s.load(root/'study_state.json')['state']=='prepared'
        approval=authorize(cfg['budget_ledger_path'],(root/'ledger_before_study.json').read_bytes(),s.sha(root/'study_plan.json'),s.sha(root/'authorization_proof.json'))
        s.atomic_json(root/'budget_authorization.json',approval)
        s.atomic_json(root/'run_environment.json',dict(started_at=s.stamp(),secondary_key_sha256=binding['secondary'],catalog=catalog,
            paid_automatic_retries=0,concurrency=cfg['concurrency']))
        s.atomic_json(root/'current_credential_batch.json',dict(slot='secondary'))
    else:
        assert s.sha(cfg['budget_ledger_path'])==s.load(root/'ledger_checkpoint.json')['sha256']
        assert binding['secondary']==s.load(root/'run_environment.json')['secondary_key_sha256']
    budget=coordinator(cfg,plan)
    completed={j['job_id'] for j in plan['jobs'] if s.load(root/'jobs'/j['condition']/(j['pid']+'.json')).get('job_done')}
    for key in completed:budget.finish(key)
    pending=[j for j in plan['jobs'] if j['job_id'] not in completed]
    for j in pending:
        assert not list((root/'jobs'/j['condition']).glob(j['pid']+'.*')),'Partial request evidence requires inspection, never resend'
    active={};cursor=0;done_count=len(completed);limit=4 if done_count<4 else 8;error=None;awake=False
    s.atomic_json(root/'active_run.json',dict(**s.old.old.support.current_process_marker(),state='running',entry='f14_v3_study.py'))
    try:
        if os.name=='nt':awake=bool(ctypes.windll.kernel32.SetThreadExecutionState(0x80000001))
        with ThreadPoolExecutor(max_workers=8,thread_name_prefix='agent-job') as pool:
            while cursor<len(pending) or active:
                while not budget.stopped.is_set() and cursor<len(pending) and len(active)<limit:
                    s.verify(cfg);job=pending[cursor];cursor+=1
                    future=pool.submit(s.generate_job,cfg,root,plan,job,budget.view(job['job_id']),{},factory=s.credentials.provider_factory)
                    active[future]=job
                    s.atomic_json(root/'study_state.json',dict(state='running',at=s.stamp(),active_jobs=[j['job_id'] for j in active.values()],workers=limit,completed=done_count))
                report(cfg,plan)
                if not active:break
                ready,_=wait(active,timeout=10,return_when=FIRST_COMPLETED)
                for future in ready:
                    job=active.pop(future)
                    try:
                        record=future.result()
                        if not record['job_done']:raise RuntimeError('Job stopped with partial evidence')
                        budget.finish(job['job_id']);done_count+=1
                        print('FINISHED',job['job_id'],done_count,'/140',flush=True)
                    except BaseException as exc:
                        error=s.sanitize(type(exc).__name__+': '+str(exc));budget.halt(error)
                if done_count>=4 and not budget.stopped.is_set():limit=8
                if ready:report(cfg,plan);publish()
        state=budget.read(allow_halted=True)
        final='completed' if done_count==140 and not error and not budget.stopped.is_set() else 'stopped'
        s.atomic_json(root/'study_state.json',dict(state=final,at=s.stamp(),completed=done_count,error=error or state.get('halted','')))
        if final=='completed':
            from f14_v3_report import audit_final
            s.atomic_json(root/'final_audit.json',audit_final(cfg,plan))
            s.atomic_json(root/'completion.json',dict(completed=True,jobs=140,requests=len(state['events'])-HISTORY,accounted_cny=state['spent_cny'],at=s.stamp()))
    except BaseException as exc:
        s.atomic_json(root/'study_state.json',dict(state='stopped',at=s.stamp(),error=s.sanitize(str(exc))));raise
    finally:
        if awake:ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
        marker=s.load(root/'active_run.json');marker.update(state=s.load(root/'study_state.json')['state'],ended_at=s.stamp());s.atomic_json(root/'active_run.json',marker)
        s.atomic_json(root/'ledger_checkpoint.json',dict(sha256=s.sha(cfg['budget_ledger_path']),at=s.stamp()))
        report(cfg,plan);publish()

def main():
    p=argparse.ArgumentParser();p.add_argument('command',choices=('prepare','check','live','resume','serve'));p.add_argument('--port',type=int,default=8888)
    args=p.parse_args();cfg=s.config()
    if args.command=='prepare':prepare(cfg)
    elif args.command=='check':s.verify(cfg);print('PASS frozen v3 source, judge, model identity and budget plan')
    elif args.command=='serve':serve(cfg,args.port)
    else:live(cfg,args.command=='resume')

if __name__=='__main__':main()

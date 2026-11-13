"""Budget-gated extension of the frozen V13 policy to complete all four groups."""
from concurrent.futures import ThreadPoolExecutor,wait,FIRST_COMPLETED
from pathlib import Path
import ctypes
import json
import os
import subprocess
import sys
import f14_v14_core as s
from f14_v14_budget import Coordinator,authorize
from f14_v14_status import report,record_for

def publish():
    assert not subprocess.check_output(['git','diff','--cached','--name-only'],cwd=s.REPO)
    subprocess.run(['git','add','--',s.MIRROR.relative_to(s.REPO).as_posix()],cwd=s.REPO,check=True,capture_output=True)
    package=s.MIRROR/'验收包.zip'
    if package.exists():subprocess.run(['git','add','-f','--',package.relative_to(s.REPO).as_posix()],cwd=s.REPO,check=True,capture_output=True)
    if subprocess.run(['git','diff','--cached','--quiet'],cwd=s.REPO).returncode:
        subprocess.run(['git','commit','-q','-m','chore: archive remaining 120-job comparison progress'],cwd=s.REPO,check=True,capture_output=True)
    try:
        subprocess.run(['git','-c','http.version=HTTP/1.1','-c','http.sslBackend=openssl','push','origin','main'],cwd=s.REPO,check=True,capture_output=True,timeout=45,
            env=dict(os.environ,GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='never'))
    except (subprocess.TimeoutExpired,subprocess.CalledProcessError) as exc:
        s.atomic_json(Path(s.config()['campaign_root'])/'sync_pending.json',dict(error=type(exc).__name__,at=s.stamp(),model_requests_retried=False))

def prepare():
    cfg=s.config();root=Path(cfg['campaign_root'])
    if (root/'prepared.json').exists():
        assert s.load(root/'study_state.json')['state']=='awaiting_budget_approval'
        assert Path(cfg['budget_ledger_path']).read_bytes()==(root/'ledger_before_study.json').read_bytes(),'Ledger changed during preparation'
        archive=root/'preparation_history'/s.sha(root/'study_plan.json');archive.mkdir(parents=True,exist_ok=True)
        for name in ('study_plan.json','prepared.json','authorization_proof.json','validation.json'):
            if not (archive/name).exists():(archive/name).write_bytes((root/name).read_bytes())
    before=Path(cfg['budget_ledger_path']).read_bytes();ledger=json.loads(before)
    assert (ledger['spent_cny'],len(ledger['events']),ledger['limit_cny'])==(s.BASELINE,s.HISTORY,420)
    validation=s.load(root/'validation.json');assert validation['passed']
    (root/'ledger_before_study.json').write_bytes(before)
    s.atomic_json(root/'authorization_proof.json',dict(user_instruction='很好，现在启动140组实验剩下的实验',
        approved_cap_cny=s.TOTAL,budget_increase_approved=s.TOTAL>420,explicit_budget_instruction=cfg.get('budget_increase_instruction','none; existing420 cap only'),max_new_requests=480,max_candidates_per_task=4,
        initial_parallel_tasks=8,max_parallel_tasks=16,output_cap=24576,completed_public20_preserved=True,
        historical_events=s.HISTORY,initial_accounted_cny=s.BASELINE))
    plan=s.build_plan(cfg,ledger);s.atomic_json(root/'study_plan.json',plan)
    s.atomic_json(root/'prepared.json',dict(plan_sha256=s.sha(root/'study_plan.json'),validation_sha256=s.sha(root/'validation.json')))
    s.atomic_json(root/'study_state.json',dict(state='prepared' if plan['funding_sufficient'] else 'awaiting_budget_approval',at=s.stamp()))
    report(cfg,plan)
    print('PREPARED: 20 imported, 120 new; worst cumulative',plan['worst_cumulative_cny'],'authorized cap',s.TOTAL,flush=True)

def audit(cfg,plan):
    root=Path(cfg['campaign_root']);state=s.load(cfg['budget_ledger_path']);before=s.load(root/'ledger_before_study.json')
    assert s.prefix_ok(state,before)
    linked={(e['request']['job_id'],e['request']['candidate_index']):e for e in state['events'][s.HISTORY:]}
    assert len(linked)==len(state['events'])-s.HISTORY<=480
    passed=0;cases=0;calls=0
    for job in plan['jobs']+plan['imported_jobs']:
        record=record_for(root,job);assert record['job_done'] and 1<=len(record['attempts'])<=4
        folder=Path(job['source_record']).parent if job.get('imported') else root/'jobs'/job['condition']
        for a in record['attempts']:
            if not job.get('imported'):
                event=linked[(job['job_id'],a['idx'])];assert event['status']=='settled'
                assert s.money(event['accounted_cny'])==s.money(a['cost_cny']);assert event['metadata']['model']==a['actual_model']
            if a.get('model_patch',{}).get('mode') in ('model_exact_edits','model_replacement'):
                from v13_repairs import apply
                base=(folder/(job['pid']+f'.patch_base_{a["idx"]+1:02}.st')).read_bytes().decode('utf-8')
                patch=s.load(folder/(job['pid']+f'.model_patch_{a["idx"]+1:02}.json'));expanded,_=apply(patch['raw_model_text'],base)
                assert s.normalize(expanded)[0]==a['code']
            if a.get('code'):assert s.sha(folder/(job['pid']+f'.candidate_{a["idx"]+1:02}.st'))==a['code_hash']
        best=record['attempts'][record['best_attempt']];passed+=best['functional_pass'];cases+=best['tests_passed']
        if not job.get('imported'):calls+=len(record['attempts'])
    assert calls==len(linked)
    result=dict(passed=True,combined_jobs=140,new_jobs=120,imported_jobs=20,new_requests=calls,functional_passed=passed,
        assertions_passed=cases,assertions_total=3784,accounted_cny=state['spent_cny'],at=s.stamp(),original_events_preserved=True)
    s.atomic_json(root/'final_audit.json',result);return result

def live():
    cfg=s.config();root=Path(cfg['campaign_root']);plan=s.verify(cfg)
    assert plan['funding_sufficient'] and s.money(s.BASELINE)+s.money(plan['worst_reservation_cny'])<=s.money(s.TOTAL),'Complete 120-job plan exceeds the authorized cumulative budget; no new request sent'
    s.old.old.support.no_other_runner(cfg);s.old.ensure_pushed()
    binding=s.credentials.load_credentials(cfg);catalog=s.credentials.catalog(cfg,'secondary')
    assert s.load(root/'study_state.json')['state']=='prepared'
    approval=authorize(cfg['budget_ledger_path'],(root/'ledger_before_study.json').read_bytes(),s.sha(root/'study_plan.json'),s.sha(root/'authorization_proof.json'),worst_reservation_cny=plan['worst_reservation_cny'])
    s.atomic_json(root/'budget_authorization.json',approval);s.atomic_json(root/'run_environment.json',dict(started_at=s.stamp(),catalog=catalog,secondary_key_sha256=binding['secondary'],automatic_model_retries=0))
    s.atomic_json(root/'current_credential_batch.json',dict(slot='secondary'))
    budget=Coordinator(cfg['budget_ledger_path'],dict(plan,sha256=s.sha(root/'study_plan.json'),ledger_before=str(root/'ledger_before_study.json')))
    s.atomic_json(root/'active_run.json',dict(**s.old.old.support.current_process_marker(),state='running',entry='f14_v14_study.py'))
    cursor=0;active={};done=0;limit=8;last_published=0;error=None
    try:
        if os.name=='nt':ctypes.windll.kernel32.SetThreadExecutionState(0x80000001)
        with ThreadPoolExecutor(max_workers=16,thread_name_prefix='v14-remaining') as pool:
            while cursor<len(plan['jobs']) or active:
                while cursor<len(plan['jobs']) and len(active)<limit and not budget.stopped.is_set():
                    s.verify(cfg);job=plan['jobs'][cursor];cursor+=1
                    active[pool.submit(s.generate_job,cfg,root,plan,job,budget.view(job['job_id']),{},factory=s.credentials.provider_factory)]=job
                s.atomic_json(root/'study_state.json',dict(state='running',new_completed=done,imported_completed=20,active_jobs=[j['job_id'] for j in active.values()],workers=limit,at=s.stamp()))
                report(cfg,plan)
                if not active:break
                ready,_=wait(active,timeout=10,return_when=FIRST_COMPLETED)
                for future in ready:
                    job=active.pop(future)
                    try:
                        record=future.result();assert record['job_done'];budget.finish(job['job_id']);done+=1
                        best=record['attempts'][record['best_attempt']];print('FINISHED',job['job_id'],best['tests_passed'],'/',best['tests_total'],'NEW',done,'/120',flush=True)
                    except BaseException as exc:
                        error=s.sanitize(type(exc).__name__+': '+str(exc));budget.halt(error)
                if done>=4:limit=16
                if done-last_published>=4:report(cfg,plan);publish();last_published=done
        assert done==120 and not budget.stopped.is_set(),error or 'Campaign stopped; in-flight receipts retained'
        result=audit(cfg,plan);s.atomic_json(root/'completion.json',dict(**result,completed=True))
        s.atomic_json(root/'study_state.json',dict(state='completed',combined_completed=140,new_completed=120,at=s.stamp()))
        budget.halt('LATEST_140_COMPLETE')
    except BaseException as exc:
        s.atomic_json(root/'study_state.json',dict(state='stopped',new_completed=done,error=s.sanitize(str(exc)),at=s.stamp()));raise
    finally:
        if os.name=='nt':ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
        s.atomic_json(root/'ledger_checkpoint.json',dict(sha256=s.sha(cfg['budget_ledger_path']),at=s.stamp()))
        s.atomic_json(root/'active_run.json',dict(state='ended',at=s.stamp()));report(cfg,plan);publish()

if __name__=='__main__':
    if sys.argv[1]=='prepare':prepare()
    elif sys.argv[1]=='live':live()
    elif sys.argv[1]=='serve':
        from f14_v11_report import serve
        serve(s.config(),8897)

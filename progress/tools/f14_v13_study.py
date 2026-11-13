"""Verify four autonomous targeted repairs, then launch a fresh self-only full run."""
from concurrent.futures import ThreadPoolExecutor,wait,FIRST_COMPLETED
from pathlib import Path
import ctypes
import json
import os
import subprocess
import sys
import f14_v13_core as s
from f14_v13_budget import Coordinator,authorize
from f14_v13_status import report

def publish():
    assert not subprocess.check_output(['git','diff','--cached','--name-only'],cwd=s.REPO)
    subprocess.run(['git','add','--',s.MIRROR.relative_to(s.REPO).as_posix()],cwd=s.REPO,check=True,capture_output=True)
    package=s.MIRROR/'验收包.zip'
    if package.exists():subprocess.run(['git','add','-f','--',package.relative_to(s.REPO).as_posix()],cwd=s.REPO,check=True,capture_output=True)
    if subprocess.run(['git','diff','--cached','--quiet'],cwd=s.REPO).returncode:
        subprocess.run(['git','commit','-q','-m','chore: archive V13 self-only validation progress'],cwd=s.REPO,check=True,capture_output=True)
    try:
        subprocess.run(['git','-c','http.version=HTTP/1.1','-c','http.sslBackend=openssl','push','origin','main'],cwd=s.REPO,check=True,capture_output=True,timeout=45,
            env=dict(os.environ,GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='never'))
    except (subprocess.TimeoutExpired,subprocess.CalledProcessError) as exc:
        s.atomic_json(Path(s.config()['campaign_root'])/'sync_pending.json',dict(error=type(exc).__name__,at=s.stamp(),model_requests_retried=False))

def prepare():
    cfg=s.config();root=Path(cfg['campaign_root']);assert not (root/'prepared.json').exists()
    before=Path(cfg['budget_ledger_path']).read_bytes();ledger=json.loads(before)
    assert (ledger['spent_cny'],len(ledger['events']),ledger['limit_cny'])==(s.BASELINE,s.HISTORY,420)
    validation=s.load(root/'validation.json');assert validation['passed']
    (root/'ledger_before_study.json').write_bytes(before)
    s.atomic_json(root/'authorization_proof.json',dict(user_instruction='验证机械臂温控、灌装线和FIFO的针对性修复；具备20/20潜力后启动DeepSeek自研20题独立全量',
        total_cap_cny=420,max_requests=88,max_candidates_per_task=4,max_parallel_tasks=8,output_cap=24576,other_groups_paused=True,
        historical_events=s.HISTORY,initial_accounted_cny=s.BASELINE))
    plan=s.build_plan(cfg,ledger);s.atomic_json(root/'study_plan.json',plan)
    s.atomic_json(root/'prepared.json',dict(plan_sha256=s.sha(root/'study_plan.json'),validation_sha256=s.sha(root/'validation.json')))
    s.atomic_json(root/'study_state.json',dict(state='prepared',phase='diagnostic',at=s.stamp()))
    report(cfg,plan)
    print('PREPARED',len(plan['jobs']),'jobs; worst cumulative',float(s.money(s.BASELINE)+s.money(plan['worst_reservation_cny'])),flush=True)

def audit(cfg,plan,phase):
    root=Path(cfg['campaign_root']);state=s.load(cfg['budget_ledger_path']);before=s.load(root/'ledger_before_study.json')
    assert s.prefix_ok(state,before)
    events=state['events'][s.HISTORY:];linked={(e['request']['job_id'],e['request']['candidate_index']):e for e in events}
    assert len(events)==len(linked)<=88
    scores=[]
    for j in [j for j in plan['jobs'] if j['phase']==phase]:
        folder=root/'jobs'/j['condition'];record=s.load(folder/(j['pid']+'.json'))
        assert record['job_done'] and 1<=len(record['attempts'])<=4
        for a in record['attempts']:
            event=linked[(j['job_id'],a['idx'])];assert event['status']=='settled'
            assert s.money(event['accounted_cny'])==s.money(a['cost_cny'])
            assert event['metadata']['model']==a['actual_model']==cfg['models'][0]['model']
            for key in ('prompt_tokens','completion_tokens'):assert event['metadata'][key]==a[key]
            if a.get('model_patch',{}).get('mode') in ('model_exact_edits','model_replacement'):
                from v13_repairs import apply
                base=(folder/(j['pid']+f'.patch_base_{a["idx"]+1:02}.st')).read_bytes().decode('utf-8')
                patch=s.load(folder/(j['pid']+f'.model_patch_{a["idx"]+1:02}.json'))
                expanded,_=apply(patch['raw_model_text'],base);assert s.normalize(expanded)[0]==a['code']
            if a.get('code'):
                assert s.sha(folder/(j['pid']+f'.candidate_{a["idx"]+1:02}.st'))==a['code_hash']
        best=record['attempts'][record['best_attempt']]
        scores.append(dict(pid=j['pid'],functional_pass=best['functional_pass'],native_pass=best['native_pass'],native_eligible=best['native_eligible'],passed=best['tests_passed'],total=best['tests_total']))
    result=dict(passed=True,phase=phase,results=scores,functional_passed=sum(v['functional_pass'] for v in scores),
        assertions_passed=sum(v['passed'] for v in scores),assertions_total=sum(v['total'] for v in scores),at=s.stamp(),other_groups_paused=True)
    s.atomic_json(root/(phase+'_audit.json'),result);return result

def live():
    cfg=s.config();root=Path(cfg['campaign_root']);plan=s.verify(cfg);s.old.old.support.no_other_runner(cfg);s.old.ensure_pushed()
    binding=s.credentials.load_credentials(cfg);catalog=s.credentials.catalog(cfg,'secondary')
    assert s.load(root/'study_state.json')['state']=='prepared'
    authorization=authorize(cfg['budget_ledger_path'],(root/'ledger_before_study.json').read_bytes(),s.sha(root/'study_plan.json'),s.sha(root/'authorization_proof.json'))
    s.atomic_json(root/'budget_authorization.json',authorization)
    s.atomic_json(root/'run_environment.json',dict(started_at=s.stamp(),secondary_key_sha256=binding['secondary'],catalog=catalog,automatic_model_retries=0))
    s.atomic_json(root/'current_credential_batch.json',dict(slot='secondary'))
    budget=Coordinator(cfg['budget_ledger_path'],dict(plan,sha256=s.sha(root/'study_plan.json'),ledger_before=str(root/'ledger_before_study.json')))
    s.atomic_json(root/'active_run.json',dict(**s.old.old.support.current_process_marker(),state='running',entry='f14_v13_study.py'))
    try:
        if os.name=='nt':ctypes.windll.kernel32.SetThreadExecutionState(0x80000001)
        # Preserve requested order; only the first two diagnostic tasks run together.
        batches=[[j for j in plan['jobs'] if j['phase']=='diagnostic' and j['pid']=='public-easy-01'],
            [j for j in plan['jobs'] if j['phase']=='diagnostic' and j['pid']=='public-hard-04'],
            [j for j in plan['jobs'] if j['phase']=='full']]
        for number,jobs in enumerate(batches):
            if number==2:
                result=audit(cfg,plan,'diagnostic')
                assert result['functional_passed']==2 and s.load(root/'prior_two_revalidated.json')['passed'] and all(v['native_pass'] or not v['native_eligible'] for v in result['results']),'Targeted repair gate not met'
                s.atomic_json(root/'full_launch_gate.json',dict(passed=True,targeted_tasks_passed=4,old_passed_tasks_replayed=16,
                    full_first_candidates_fresh=True,frozen_plan_sha256=s.sha(root/'study_plan.json'),at=s.stamp()))
                report(cfg,plan);publish();print('LAUNCH FRESH FULL 20 SELF DEEPSEEK',flush=True)
            active={};cursor=0
            with ThreadPoolExecutor(max_workers=8,thread_name_prefix='v13-self') as pool:
                while cursor<len(jobs) or active:
                    while cursor<len(jobs) and len(active)<8 and not budget.stopped.is_set():
                        s.verify(cfg);job=jobs[cursor];cursor+=1
                        active[pool.submit(s.generate_job,cfg,root,plan,job,budget.view(job['job_id']),{},factory=s.credentials.provider_factory)]=job
                    s.atomic_json(root/'study_state.json',dict(state='running',phase=jobs[0]['phase'],batch=number,active_jobs=[j['job_id'] for j in active.values()],at=s.stamp()))
                    report(cfg,plan)
                    ready,_=wait(active,timeout=10,return_when=FIRST_COMPLETED)
                    for future in ready:
                        job=active.pop(future)
                        try:
                            record=future.result();assert record['job_done']
                            budget.finish(job['job_id']);best=record['attempts'][record['best_attempt']]
                            print('FINISHED',job['job_id'],best['tests_passed'],'/',best['tests_total'],flush=True)
                            if number<2:assert best['functional_pass'] and (best['native_pass'] or not best['native_eligible']),'Targeted repair still fails'
                        except BaseException as exc:budget.halt(s.sanitize(type(exc).__name__+': '+str(exc)));raise
                    if ready:report(cfg,plan);publish()
                    if budget.stopped.is_set() and not active:raise RuntimeError('Campaign stopped; evidence retained')
        result=audit(cfg,plan,'full')
        s.atomic_json(root/'completion.json',dict(**result,completed=True,accounted_cny=budget.read()['spent_cny']))
        s.atomic_json(root/'study_state.json',dict(state='completed',phase='full',at=s.stamp()))
        budget.halt('V13_SELF_FULL_COMPLETED_OTHER_GROUPS_PAUSED')
    except BaseException as exc:
        s.atomic_json(root/'study_state.json',dict(state='stopped',error=s.sanitize(type(exc).__name__+': '+str(exc)),at=s.stamp()));raise
    finally:
        if os.name=='nt':ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
        s.atomic_json(root/'ledger_checkpoint.json',dict(sha256=s.sha(cfg['budget_ledger_path']),at=s.stamp()))
        s.atomic_json(root/'active_run.json',dict(state='ended',at=s.stamp()))
        report(cfg,plan);publish()

if __name__=='__main__':
    if sys.argv[1]=='prepare':prepare()
    elif sys.argv[1]=='live':live()
    elif sys.argv[1]=='serve':
        from f14_v11_report import serve
        serve(s.config(),8896)

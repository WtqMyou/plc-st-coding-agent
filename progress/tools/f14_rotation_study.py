"""Independent F1.4 credential batches: primary before 75, secondary until 80 review."""
import argparse
from collections import Counter
import ctypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import f14_study as base
from f14_rotation_budget import KIND,TOTAL,REVIEW,SWITCH,BASELINE,HISTORY,StudyBudget,KeySwitch,ReviewPause,authorize,prefix_ok
import f14_rotation_credentials as credentials
from stbench.billing import money
REPO,RELEASE=base.REPO,base.RELEASE
load,sha,stamp,atomic_json=base.load,base.sha,base.stamp,base.atomic_json
CONFIG=REPO/'progress/f14_rotation/config.json'
MIRROR=REPO/'progress/evidence/f14_p1_20261111b'

def sanitize(text):
    value=os.environ.get(credentials.SECONDARY_ENV,'')
    return base.sanitize(text.replace(value,'[redacted]') if len(value)>12 else text)

def config():
    cfg=load(CONFIG);prior=base.config()
    for key in ('models','limits','budget_cny','system','fifo_native_policy','budget_ledger_path','codesys_executable','codesys_profile','codesys_template'):
        assert cfg[key]==prior[key],key
    assert cfg['study']==dict(prior['study'],kind=KIND)
    assert cfg['credential_rotation']==dict(switch_shared_accounted_cny=75,review_shared_accounted_cny=80,
        same_provider_model_parameters_and_configured_prices_confirmed=True,
        secondary_dpapi_path='E:/PLC_Dev/private_credentials/f14_secondary_20261111/secondary.dpapi')
    return cfg

def files():
    return base.files()+[Path(__file__),Path(credentials.__file__),Path(__file__).with_name('f14_rotation_budget.py'),
        Path(__file__).with_name('f14_rotation_report.py'),CONFIG,CONFIG.parent/'实验方案.md',REPO/'progress/tests/test_f14_rotation.py']

def build_plan(cfg,before):
    plan=base.build_plan(cfg,before)
    plan.update(kind=KIND,files={p.relative_to(REPO).as_posix():sha(p) for p in files()},
        credential_rotation=cfg['credential_rotation'],credential_batches=['primary','secondary'],
        secondary_cipher_sha256=sha(cfg['credential_rotation']['secondary_dpapi_path']))
    return plan

def verify(cfg):
    root=Path(cfg['campaign_root']);plan=load(root/'study_plan.json');prepared=load(root/'prepared.json')
    assert sha(root/'study_plan.json')==prepared['plan_sha256'] and sha(root/'validation.json')==prepared['validation_sha256']
    assert plan['files']=={p.relative_to(REPO).as_posix():sha(p) for p in files()},'Source/config changed; separate batch required'
    assert plan['release_files']=={p.relative_to(RELEASE).as_posix():sha(p) for p in RELEASE.rglob('*') if p.is_file()}
    assert plan['secondary_cipher_sha256']==sha(cfg['credential_rotation']['secondary_dpapi_path']),'Sealed credential changed'
    assert plan['cli_identity']==base.old.old.cli_identity() and plan['native_identity']==base.old.old.support.CodesysBackend(cfg).identity()
    assert sha(root/'credential_bindings.private.json')==prepared['private_binding_sha256']
    base.old.verify(Path(base.old.config()['campaign_root']))
    assert sha(Path(base.old.config()['campaign_root'])/'验收包.zip')==plan['old_paid_package_sha256']
    return plan

def history(cfg,root,plan):
    state=load(cfg['budget_ledger_path']);before=load(root/'ledger_before_study.json');new=state['events'][HISTORY:]
    assert prefix_ok(state,before) and len(new)<=280
    keys=[(e['request']['job_id'],e['request']['candidate_index']) for e in new]
    assert len(keys)==len(set(keys)) and all(index in (0,1) for _,index in keys)
    allowed={j['job_id'] for j in plan['jobs']};seen_secondary=False;job_batches={}
    for event in new:
        assert event['phase']==KIND and event['request']['job_id'] in allowed
        slot=event['request']['credential_batch'];assert slot in ('primary','secondary')
        if slot=='secondary':seen_secondary=True
        else:assert not seen_secondary,'Must not return to the primary credential'
        job_id=event['request']['job_id'];assert job_batches.setdefault(job_id,slot)==slot,'A job cannot straddle credential batches'
    accounted=money(BASELINE)+sum((money(e.get('accounted_cny',e['reserved_cny'])) for e in new),money(0))
    assert accounted==money(state['spent_cny']) and accounted<=money(TOTAL)
    return state

def bind_batch(cfg,root,plan,slot,catalog,pending):
    previous=load(root/'current_credential_batch.json');path=root/'credential_batches'/(slot+'.json')
    assert slot in ('primary','secondary')
    if previous:
        assert previous['slot']=='primary' and slot=='secondary'
        old_path=root/'credential_batches/primary.json';old=load(old_path)
        old.update(state='closed_before_75',closed_at=stamp(),closing_spent_cny=load(cfg['budget_ledger_path'])['spent_cny'])
        atomic_json(old_path,old)
    assert not path.exists(),'Never overwrite an existing credential batch'
    snapshot=load(cfg['budget_ledger_path'])
    item=dict(batch_id=KIND+'-'+slot,slot=slot,state='active',opened_at=stamp(),
        start_shared_accounted_cny=snapshot['spent_cny'],start_ledger_events=len(snapshot['events']),
        endpoint='https://www.dmxapi.cn/v1',model_specs=cfg['models'],catalog=catalog,
        parent_plan_sha256=sha(root/'study_plan.json'),remaining_jobs=list(pending))
    atomic_json(path,item);atomic_json(root/'current_credential_batch.json',dict(slot=slot,batch_id=item['batch_id'],at=stamp()))
    return item

def publish():
    assert not subprocess.check_output(['git','diff','--cached','--name-only'],cwd=REPO)
    for file in MIRROR.rglob('*'):
        if file.is_file() and file.suffix!='.zip':assert sanitize(file.read_text(encoding='utf-8'))==file.read_text(encoding='utf-8')
    subprocess.run(['git','add','--',MIRROR.relative_to(REPO).as_posix()],cwd=REPO,check=True,capture_output=True)
    if subprocess.run(['git','diff','--cached','--quiet'],cwd=REPO).returncode:
        subprocess.run(['git','commit','-q','-m','chore: archive F1.4 credential-batch progress'],cwd=REPO,check=True,capture_output=True)
    env=dict(os.environ,GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='never')
    subprocess.run(['git','-c','http.version=HTTP/1.1','-c','http.lowSpeedLimit=1000','-c','http.lowSpeedTime=30','push','origin','main'],
        cwd=REPO,env=env,check=True,capture_output=True,timeout=60)

def prepare(cfg):
    from f14_rotation_report import report
    root=Path(cfg['campaign_root']);assert not root.exists();base.old.old.support.no_other_runner(cfg)
    before=Path(cfg['budget_ledger_path']).read_bytes();state=json.loads(before)
    assert (len(state['events']),state['spent_cny'],state['limit_cny'],bool(state.get('halted')))==(653,BASELINE,170,False)
    binding=credentials.load_credentials(cfg)
    catalogs={slot:credentials.catalog(cfg,slot) for slot in ('primary','secondary')}
    plan=build_plan(cfg,state)
    proc=subprocess.run([sys.executable,'-B','-X','utf8','-m','unittest','discover','-s','progress/tests','-p','test_f14_rotation.py','-q'],cwd=REPO,capture_output=True,text=True,encoding='utf-8',timeout=120)
    assert proc.returncode==0,proc.stderr[-1500:]
    assert Path(cfg['budget_ledger_path']).read_bytes()==before
    root.mkdir(parents=True);(root/'ledger_before_study.json').write_bytes(before)
    atomic_json(root/'credential_bindings.private.json',binding)
    atomic_json(root/'study_plan.json',plan)
    atomic_json(root/'validation.json',dict(passed=True,tests=proc.stderr,prior_controller_tests=30,
        prior_prepared_plan_sha256=sha(Path(base.config()['campaign_root'])/'study_plan.json'),
        catalogs=catalogs,generation_requests=0,ledger_unchanged=True))
    atomic_json(root/'prepared.json',dict(plan_sha256=sha(root/'study_plan.json'),validation_sha256=sha(root/'validation.json'),
        private_binding_sha256=sha(root/'credential_bindings.private.json')))
    atomic_json(root/'study_state.json',dict(state='prepared',at=stamp()));report(cfg,plan)
    print('PREPARED independent 75/80 credential batches; authenticated catalogs only, zero generation requests',flush=True)

def audit_final(cfg,root,plan):
    state=history(cfg,root,plan);linked={(e['request']['job_id'],e['request']['candidate_index']):e for e in state['events'][HISTORY:]};count=0
    for job in plan['jobs']:
        record=load(root/'jobs'/job['condition']/(job['pid']+'.json'))
        assert record['job_done'] and 1<=len(record['attempts'])<=2
        assert record['best_attempt']==base.select_best(record['attempts']) and record['study_plan_sha256']==sha(root/'study_plan.json')
        for index,attempt in enumerate(record['attempts']):
            event=linked[(job['job_id'],index)];assert event['status']=='settled' and money(event['accounted_cny'])==money(attempt['cost_cny'])
            assert event['request']['credential_batch']==record['credential_batch']
            assert attempt['actual_model']==event['metadata']['model']
            for field in ('prompt_tokens','completion_tokens'):assert attempt[field]==event['metadata'][field]
            if attempt['code']:assert hashlib.sha256(attempt['code'].encode()).hexdigest()==attempt['code_hash']
            count+=1
    assert count==len(linked)<=280
    return dict(passed=True,jobs=140,requests=count,ledger_sha256=sha(cfg['budget_ledger_path']),credential_batches_separate=True,at=stamp())

def live(cfg,resume=False):
    from f14_rotation_report import report
    root=Path(cfg['campaign_root']);plan=verify(cfg);base.old.old.support.no_other_runner(cfg)
    state=load(root/'study_state.json');assert state['state'] in (('stopped','running') if resume else ('prepared',))
    head=base.old.ensure_pushed()
    assert credentials.load_credentials(cfg)==load(root/'credential_bindings.private.json'),'Credential identity changed; new batch required'
    catalogs={slot:credentials.catalog(cfg,slot) for slot in ('primary','secondary')}
    before=(root/'ledger_before_study.json').read_bytes();assert hashlib.sha256(before).hexdigest()==plan['initial_ledger_sha256']
    if not resume:
        approval=authorize(cfg['budget_ledger_path'],before,sha(root/'study_plan.json'),stamp())
        atomic_json(root/'budget_authorization.json',approval)
        atomic_json(root/'run_environment.json',dict(published_preparation_commit=head,started_at=stamp(),catalogs=catalogs,automatic_retries=0))
        base.checkpoint(cfg,root)
    else:assert sha(cfg['budget_ledger_path'])==load(root/'ledger_checkpoint.json')['sha256']
    history(cfg,root,plan);pending=base.remaining(root,plan)
    if not resume:bind_batch(cfg,root,plan,'primary',catalogs['primary'],pending)
    slot=load(root/'current_credential_batch.json')['slot'];budget=StudyBudget(cfg['budget_ledger_path'],sha(root/'study_plan.json'),slot)
    final='stopped';awake=False;current_job=None
    atomic_json(root/'active_run.json',dict(**base.old.old.support.current_process_marker(),state='running',entry='f14_rotation_study.py'))
    try:
        report(cfg,plan);publish()
        if os.name=='nt':awake=bool(ctypes.windll.kernel32.SetThreadExecutionState(0x80000001))
        for job in plan['jobs']:
            if job['job_id'] not in pending:continue
            current_job=job;verify(cfg);assert sha(cfg['budget_ledger_path'])==load(root/'ledger_checkpoint.json')['sha256']
            history(cfg,root,plan)
            try:
                try:budget.admit_job(pending[job['job_id']])
                except KeySwitch:
                    assert budget.active_batch=='primary'
                    secondary_catalog=credentials.catalog(cfg,'secondary')
                    bind_batch(cfg,root,plan,'secondary',secondary_catalog,pending);budget.active_batch='secondary'
                    report(cfg,plan);publish();budget.admit_job(pending[job['job_id']])
            except ReviewPause as exc:
                final='paused_for_api_review';atomic_json(root/'study_state.json',dict(state=final,at=stamp(),reason=str(exc),next_job=job['job_id'],remaining_jobs=list(pending)));break
            atomic_json(root/'study_state.json',dict(state='running',at=stamp(),current_job=job['job_id'],credential_batch=budget.active_batch));report(cfg,plan)
            result=base.generate_job(cfg,root,plan,job,budget,pending,factory=credentials.provider_factory)
            assert result['job_done'];result['credential_batch']=budget.active_batch
            atomic_json(root/'jobs'/job['condition']/(job['pid']+'.json'),result)
            snapshot=history(cfg,root,plan);assert snapshot['events'][-1]['status']=='settled'
            pending.pop(job['job_id']);base.checkpoint(cfg,root);summary=report(cfg,plan);publish()
            print('FINISHED',job['job_id'],summary['recorded'],'/140',budget.active_batch,snapshot['spent_cny'],'CNY',flush=True)
        else:
            atomic_json(root/'final_audit.json',audit_final(cfg,root,plan));final='completed'
            atomic_json(root/'study_state.json',dict(state=final,at=stamp()))
            atomic_json(root/'completion.json',dict(completed=True,recorded=140,requests=len(snapshot['events'])-HISTORY,total_accounted_cny=snapshot['spent_cny'],ended_at=stamp()))
    except BaseException as exc:
        if current_job:
            path=root/'jobs'/current_job['condition']/(current_job['pid']+'.json');record=load(path)
            if record:record['credential_batch']=budget.active_batch;atomic_json(path,record)
        atomic_json(root/'study_state.json',dict(state='stopped',at=stamp(),error=sanitize(type(exc).__name__+': '+str(exc))));raise
    finally:
        if awake:ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
        marker=load(root/'active_run.json');marker.update(state=final,ended_at=stamp());atomic_json(root/'active_run.json',marker)
        base.checkpoint(cfg,root);report(cfg,plan);publish()

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('command',choices=('prepare','check','live','resume','serve'));parser.add_argument('--port',type=int,default=8885)
    args=parser.parse_args();cfg=config()
    if args.command=='prepare':prepare(cfg)
    elif args.command=='check':verify(cfg);history(cfg,Path(cfg['campaign_root']),load(Path(cfg['campaign_root'])/'study_plan.json'));print('PASS frozen 75/80 credential-batch study')
    elif args.command=='serve':
        from f14_rotation_report import serve
        serve(cfg,args.port)
    else:live(cfg,args.command=='resume')

if __name__=='__main__':main()

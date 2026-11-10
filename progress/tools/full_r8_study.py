"""Fresh 35-task, four-arm study with bounded repair and a manual spending checkpoint."""
from contextlib import ExitStack
import argparse
import copy
import ctypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time
from collections import Counter
from dataclasses import replace
sys.path.insert(0,str(Path(__file__).resolve().parent))
import review_r8_first_candidate as old
from full_r8_budget import StudyBudget, ReviewPause, migrate, prefix_ok, TOTAL, REVIEW, BASELINE, HISTORY
from stbench.billing import money
from stbench.evaluation import atomic_json, verification_status, feedback_for_agent
from stbench.harness.engine import RunRecord, Attempt
from stbench.providers.base import ProviderError, extract_code
from stbench.transport import MeteredProvider
from stbench.codex_baseline import CodexProvider, ResponsesGateway
from stbench.live import validate_live_config

REPO=old.REPO
CONFIG=REPO/'progress/full_r8/config.json'
MIRROR=REPO/'progress/evidence/full_r8_20261110'
KIND='full_r8_20261110'
ARMS=(('custom','deepseek-v4pro'),('codex','deepseek-v4pro'),('custom','minimax-m27'),('codex','minimax-m27'))
ORDERS=((0,1,2,3),(3,2,1,0),(1,0,3,2),(2,3,0,1))
load,sha,stamp=old.load,old.sha,old.stamp

def config():
    cfg=load(CONFIG);validate_live_config(cfg)
    if cfg['models']!=load(old.CONFIG)['models'] or cfg['strategy']!=load(old.CONFIG)['strategy']:
        raise RuntimeError('Frozen models, prices, parameters or prompts changed')
    expected=dict(kind=KIND,total_cap_cny=TOTAL,review_pause_cny=REVIEW,max_requests=280,
                  initial_spent_cny=BASELINE,initial_event_count=HISTORY,repair_input_bytes=65536)
    assert cfg['budget_cny']==TOTAL and cfg['study']==expected
    assert cfg['limits']==dict(load(old.CONFIG)['limits'],max_candidates=2)
    assert Path(cfg['budget_ledger_path']).resolve()==Path('E:/PLC_Dev/evidence/dmxapi_budget_75.json').resolve()
    return cfg

def data():
    result={p.pid:p for p in old.v.problems()}
    assert len(result)==35 and sum(len(p.test_cases) for p in result.values())==1214
    for p in result.values():p.mc_max_seconds=30.
    return result

def jobs():
    return [dict(pid=pid,framework=ARMS[i][0],model_id=ARMS[i][1],
                 condition='_'.join(ARMS[i]),job_id='_'.join(ARMS[i])+'/'+pid)
            for n,pid in enumerate(data()) for i in ORDERS[n%4]]

def source_files():
    return [Path(__file__),REPO/'progress/tools/full_r8_budget.py',REPO/'progress/tools/full_r8_report.py',
            CONFIG,CONFIG.parent/'实验方案.md',REPO/'progress/tests/test_full_r8_study.py']

def task_messages(cfg,job,p):
    return old.messages_for(cfg,job,p)

def repair_messages(messages,a):
    return messages+[dict(role='assistant',content=a.code),
                     dict(role='user',content=a.feedback[:4000]+'\n修复并返回完整代码，保持题面接口。')]

def make_plan(cfg,state,routes):
    assert (state.get('version'),state.get('limit_cny'),state['spent_cny'],len(state['events']),bool(state['halted']))==(3,75,BASELINE,HISTORY,False)
    specs={m['id']:m for m in cfg['models']};problems=data();work=jobs()
    measured={r['job_id']:r for r in routes}
    for job in work:
        m=specs[job['model_id']]
        bound=money(old.first_candidate_bound(m,problems[job['pid']],cfg,job['framework']))
        if job['job_id'] in measured:
            bound=max(bound,money(((measured[job['job_id']]['upstream_message_bytes']+6144)*m['input_cny_per_million']+16384*m['output_cny_per_million'])/1e6))
        job['first_upper_cny']=float(bound)
        job['repair_upper_cny']=float(money((65536*m['input_cny_per_million']+16384*m['output_cny_per_million'])/1e6))
        job['prompt_sha256']=old.obj_sha(task_messages(cfg,job,problems[job['pid']]))
    upper=sum((money(j['first_upper_cny'])+money(j['repair_upper_cny']) for j in work),money(0))
    assert money(BASELINE)+upper<=money(TOTAL),'Full coverage must fit before any live call'
    return dict(kind=KIND,planned=140,maximum_requests=280,initial_spent_cny=BASELINE,initial_event_count=HISTORY,
                total_cap_cny=TOTAL,review_pause_cny=REVIEW,worst_reservation_cny=float(upper),
                jobs=work,files={p.relative_to(REPO).as_posix():sha(p) for p in source_files()},
                r8_snapshot_sha256=sha(old.v.ROOT/'snapshot_manifest.json'),cli_identity=old.cli_identity())

def verify(root):
    old.verify_data()
    plan=load(root/'study_plan.json');prepared=load(root/'prepared.json')
    assert plan['files']=={p.relative_to(REPO).as_posix():sha(p) for p in source_files()},'Study source changed'
    assert prepared['plan_sha256']==sha(root/'study_plan.json') and prepared['validation_sha256']==sha(root/'validation.json')
    assert old.cli_identity()==plan['cli_identity'],'CLI identity changed'
    assert plan['r8_snapshot_sha256']==sha(old.v.ROOT/'snapshot_manifest.json')
    validation=load(root/'validation.json')
    for name in ('native_preflight.json','offline_routes.json'):
        assert sha(root/name)==validation['evidence_sha256'][name]

def history(cfg,root,plan):
    state=load(cfg['budget_ledger_path']);before=load(root/'ledger_before_study.json')
    assert prefix_ok(state,before),'Original history or recoveries changed'
    new=state['events'][HISTORY:];assert len(new)<=280
    counts=Counter((e.get('request',{}).get('job_id'),e.get('request',{}).get('candidate_index')) for e in new)
    assert all(n==1 for n in counts.values()),'Duplicate job candidate charge'
    allowed={j['job_id'] for j in plan['jobs']}
    assert all(e.get('request',{}).get('job_id') in allowed and e.get('phase')==KIND for e in new),'Unrelated ledger request'
    assert money(BASELINE)+sum((money(e.get('accounted_cny',e['reserved_cny'])) for e in new),money(0))==money(state['spent_cny']),'Accounted amount drifted'
    return state

def capture(transport,budget,job,idx,pending,folder):
    count=[0];lock=threading.Lock()
    def before(messages):
        with lock:
            if count[0]:raise ProviderError('Only one upstream request per candidate')
            upper=money(transport.upper(messages))
            bound=money(job['first_upper_cny'] if idx==0 else job['repair_upper_cny'])
            if upper>bound:raise ProviderError('Frozen input bound exceeded; no request sent')
            future=sum((money(x) for k,x in pending.items() if k!=job['job_id']),money(0))
            budget.protected_cny=float(future+(money(job['repair_upper_cny']) if idx==0 else money(0)))
            budget.context=dict(job_id=job['job_id'],candidate_index=idx,study_kind=KIND)
            path=folder/(job['pid']+f'.request_{idx+1:02}.json')
            if path.exists():raise ProviderError('Existing request trace; no retry')
            count[0]+=1
            payload=dict(model=transport.model,protocol=transport.protocol,max_tokens=16384,
                         timeout_seconds=420,parameters=transport.spec.get('parameters',{}),messages=messages)
            atomic_json(path,json.loads(old.support.sanitize(json.dumps(payload,ensure_ascii=False))))
    def response(raw,protocol):
        choice=(raw.get('choices') or [{}])[0];message=choice.get('message') or {}
        if protocol=='responses':
            message=dict(content=''.join(c.get('text','') for x in raw.get('output',[]) if x.get('type')=='message' for c in x.get('content',[]) if c.get('type')=='output_text'))
        item=dict(model=raw.get('model'),protocol=protocol,usage=raw.get('usage'),
                  finish_reason=raw.get('status') if protocol=='responses' else choice.get('finish_reason'),
                  message=message,raw_response=raw)
        atomic_json(folder/(job['pid']+f'.response_{idx+1:02}.json'),
                    json.loads(old.support.sanitize(json.dumps(item,ensure_ascii=False))))
    if not hasattr(transport,'full_r8_sender'):transport.full_r8_sender=transport.sender
    def sender(*args):
        raw=transport.full_r8_sender(*args)
        response(raw,transport.protocol)
        return raw
    transport.sender=sender
    transport.before_send=before;transport.response_observer=response
    return count

def public_failure(result):
    native=result.platform_results.get('codesys',{}).get('status')
    if native in ('timeout','tool_error','unavailable'):return True
    # A normal bounded formal timeout is not a shared-tool failure.
    return result.evidence_metadata.get('classification')=='tool_error' and not result.mc_error.startswith('r7 worker timeout')

def repairable(result):
    if public_failure(result):return False
    if result.evidence_metadata.get('classification') in ('unsupported_modeling','tool_error'):return False
    if result.mc_specs_violated:return True
    if result.compiles and result.all_tests_passed and all(x['status']=='passed' for x in result.platform_results.values()):return False
    return (bool(result.compile_errors) or result.platform_results.get('codesys',{}).get('status')=='failed'
            or result.evidence_metadata.get('classification')=='evaluated' and not result.all_tests_passed)

def envelope(record,root,done):
    result=record.to_dict()
    result.update(job_done=done,study_plan_sha256=sha(root/'study_plan.json'),
                  complete_code=bool(record.best and old.compile_st(record.best.code).ok and old.compile_st(record.best.code).pou is not None))
    return result

def generate_job(cfg,root,plan,job,budget,pending,*,factory=MeteredProvider,evaluator=None):
    folder=root/'jobs'/job['condition'];folder.mkdir(parents=True,exist_ok=True)
    if list(folder.glob(job['pid']+'.*')):raise RuntimeError('Existing job trace; no implicit retry')
    m=next(x for x in cfg['models'] if x['id']==job['model_id']);p=data()[job['pid']]
    started=time.monotonic();deadline=started+1200
    record=RunRecord(p.pid,m['model'],'custom' if job['framework']=='custom' else 'codex-cli',
                     job['condition'],2,experiment_kind='live',tests_total=len(p.test_cases),request_window_seconds=450)
    requests=0;done=False;fatal=None;messages=task_messages(cfg,job,p)
    try:
        with ExitStack() as stack:
            transport=factory(m,budget,max_tokens=16384,protocol=m['generation_protocol'],timeout=420)
            provider=transport
            if job['framework']=='codex':
                gateway=stack.enter_context(ResponsesGateway(provider=transport,model=transport.model))
                provider=CodexProvider(gateway,model=transport.model,work_root=Path(cfg['platform_root'])/'builds/full_r8_live',timeout=450)
            for idx in range(2):
                if deadline-time.monotonic()<450:
                    record.stop_reason='insufficient_request_window';done=True;break
                sent=capture(transport,budget,job,idx,pending,folder)
                call_started=time.monotonic()
                try:
                    response=provider.generate(messages);source=extract_code(response.text)
                    code_hash=hashlib.sha256(source.encode()).hexdigest()
                    if idx and code_hash==record.attempts[0].code_hash:
                        a=replace(record.attempts[0],idx=idx,feedback='候选重复，停止无效循环。',
                            prompt_tokens=response.usage['prompt_tokens'],completion_tokens=response.usage['completion_tokens'],
                            latency_s=time.monotonic()-call_started,cost_cny=response.cost_cny,actual_model=response.model)
                        record.add(a);record.stop_reason='repeated_candidate';done=True;break
                    remaining=max(0,deadline-time.monotonic())
                    result=(evaluator(source,p) if evaluator else old.judge.evaluate(source,p,model_check=True,
                            timeout_s=remaining,task_remaining_s=remaining,verification_after_tests=True,
                            backends=(old.support.CodesysBackend(cfg),)))
                    feedback=feedback_for_agent(result)
                    a=Attempt(idx,source,result.compiles,result.tests_passed,len(p.test_cases),feedback=feedback,
                              code_hash=code_hash,judge=result.to_dict(),platform_results=result.platform_results,
                              verification_status=verification_status(result),actual_model=response.model,
                              prompt_tokens=response.usage['prompt_tokens'],completion_tokens=response.usage['completion_tokens'],
                              latency_s=time.monotonic()-call_started,cost_cny=response.cost_cny)
                    record.add(a)
                    if public_failure(result):
                        fatal=RuntimeError('Shared evaluation tool failure');record.stop_reason='shared_tool_error';break
                    if not repairable(result):
                        record.stop_reason='functional_pass_formal_'+verification_status(result) if a.solved else 'not_repairable'
                        done=True;break
                    if idx==1:
                        record.stop_reason='max_candidates';done=True;break
                    messages=repair_messages(task_messages(cfg,job,p),a)
                except ProviderError as exc:
                    receipt=transport.last_receipt;record.error=old.support.sanitize(str(exc))
                    known=record.error.startswith('Generation incomplete/empty:')
                    record.add(Attempt(idx,'',False,0,len(p.test_cases),provider_error=record.error,
                               actual_model=receipt.get('model',''),prompt_tokens=receipt.get('prompt_tokens',0),
                               completion_tokens=receipt.get('completion_tokens',0),
                               latency_s=time.monotonic()-call_started,cost_cny=transport.last_charge))
                    record.stop_reason='generation_incomplete' if known else 'provider_error'
                    if known:done=True
                    else:fatal=exc
                    break
                finally:
                    requests+=sent[0]
                    record.finished_at=time.time()
                    atomic_json(folder/(p.pid+'.json'),envelope(record,root,done))
    finally:
        record.finished_at=time.time()
        atomic_json(folder/(p.pid+'.json'),envelope(record,root,done))
        atomic_json(folder/(p.pid+'.timing.json'),dict(job_id=job['job_id'],upstream_requests_entered=requests,
                    wall_seconds=time.monotonic()-started,finished_at=stamp()))
    if fatal:raise fatal
    return envelope(record,root,done)

def offline_routes(cfg,root):
    rows=[];problems=data();specs={m['id']:m for m in cfg['models']}
    for job in jobs():
        p=problems[job['pid']];source=old.v.reference(p)
        fixture=old.Fixture(specs[job['model_id']]['model'],source)
        with ExitStack() as stack:
            provider=fixture
            if job['framework']=='codex':
                gateway=stack.enter_context(ResponsesGateway(provider=fixture,model=fixture.model))
                provider=CodexProvider(gateway,model=fixture.model,work_root=Path(cfg['platform_root'])/'builds/full_r8_offline',mock=True,timeout=60)
            result=provider.generate(task_messages(cfg,job,p))
        assert result.text.strip()==source.strip()
        checked=old.judge.local_tests(result.text,p);assert checked.compiles and checked.all_tests_passed
        assert source.strip() not in json.dumps(fixture.messages,ensure_ascii=False)
        target=root/'frozen_requests'/job['condition']/(p.pid+'.json')
        atomic_json(target,dict(messages=fixture.messages,model=fixture.model,external_requests=0))
        rows.append(dict(job_id=job['job_id'],upstream_message_bytes=len(json.dumps(fixture.messages,ensure_ascii=False).encode()),
                         upstream_messages_sha256=old.obj_sha(fixture.messages),tests_passed=checked.tests_passed,external_requests=0))
        print('OFFLINE',job['job_id'],flush=True)
    atomic_json(root/'offline_routes.json',dict(passed=True,routes=rows,external_requests=0))
    return rows

def prepare(cfg):
    root=Path(cfg['campaign_root'])
    assert not root.exists(),'Existing campaign is never overwritten'
    old.verify_data();old.support.no_other_runner(cfg)
    before=Path(cfg['budget_ledger_path']).read_bytes()
    make_plan(cfg,json.loads(before),[])
    root.mkdir(parents=True)
    (root/'ledger_before_study.json').write_bytes(before)
    suites=[]
    for pattern in ('test_full_r8_study.py','test_review_r8_first_candidate.py','test_v13_r8.py','test_v13_r7.py','test_v13_r6.py','test_v13_r5.py','test_v13_r4.py'):
        proc=subprocess.run([sys.executable,'-B','-X','utf8','-m','unittest','discover','-s','progress/tests','-p',pattern,'-q'],
                            cwd=REPO,capture_output=True,text=True,encoding='utf-8',timeout=180)
        (root/(pattern+'.log')).write_bytes((proc.stdout+'\n'+proc.stderr).encode())
        assert proc.returncode==0,proc.stderr[-1800:]
        suites.append(dict(pattern=pattern,passed=True))
    rows=offline_routes(cfg,root)
    plan=make_plan(cfg,json.loads(before),rows);plan['initial_ledger_sha256']=hashlib.sha256(before).hexdigest()
    native=load(Path(load(old.CONFIG)['campaign_root'])/'native_preflight.json')
    for backend in (old.support.CodesysBackend(cfg),old.support.OpenPLCBackend(cfg)):
        assert native[backend.name]['positive']['status']=='passed' and native[backend.name]['negative']['status']=='failed'
        assert native[backend.name]['positive']['platform_identity']==backend.identity(),'Native tool identity changed'
    atomic_json(root/'native_preflight.json',native)
    assert Path(cfg['budget_ledger_path']).read_bytes()==before
    atomic_json(root/'study_plan.json',plan)
    atomic_json(root/'validation.json',dict(passed=True,suites=suites,offline_routes=140,actual_codex_cli_routes=70,
                external_requests=0,ledger_unchanged=True,native_controls_reused_from=load(old.CONFIG)['campaign_root'],
                evidence_sha256={name:sha(root/name) for name in ('native_preflight.json','offline_routes.json')}))
    atomic_json(root/'prepared.json',dict(plan_sha256=sha(root/'study_plan.json'),validation_sha256=sha(root/'validation.json')))
    atomic_json(root/'study_state.json',dict(state='prepared',at=stamp()))
    from full_r8_report import report
    report(cfg,plan)
    print('PREPARED',len(plan['jobs']),'jobs; maximum',plan['worst_reservation_cny'],'CNY; zero model calls',flush=True)

def publish():
    env=dict(os.environ,GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='never')
    assert subprocess.check_output(['git','branch','--show-current'],cwd=REPO,text=True).strip()=='main'
    assert not subprocess.check_output(['git','diff','--cached','--name-only'],cwd=REPO),'Other staged work; stop publishing'
    for p in MIRROR.rglob('*'):
        if p.is_file():
            if p.suffix=='.zip':
                import zipfile
                with zipfile.ZipFile(p) as archive:
                    assert archive.testzip() is None
                    contents=[archive.read(n).decode('utf-8') for n in archive.namelist()]
            else:contents=[p.read_text('utf-8')]
            assert all(old.support.sanitize(content)==content for content in contents),'Sensitive content in public evidence'
    subprocess.run(['git','add','--',MIRROR.relative_to(REPO).as_posix()],cwd=REPO,check=True,capture_output=True)
    if subprocess.run(['git','diff','--cached','--quiet'],cwd=REPO).returncode:
        subprocess.run(['git','commit','-q','-m','chore: archive full r8 experiment progress'],cwd=REPO,check=True,capture_output=True)
        subprocess.run(['git','push','origin','main'],cwd=REPO,env=env,check=True,capture_output=True,timeout=60)

def checkpoint(cfg,root):
    state=load(cfg['budget_ledger_path'])
    atomic_json(root/'ledger_checkpoint.json',dict(sha256=sha(cfg['budget_ledger_path']),
                events=len(state['events']),spent_cny=state['spent_cny'],at=stamp()))

def remaining_jobs(root,plan):
    pending={}
    for job in plan['jobs']:
        folder=root/'jobs'/job['condition'];record=load(folder/(job['pid']+'.json'))
        if record:
            assert record.get('job_done'),'Partial job requires investigation, not automatic resume'
            continue
        assert not list(folder.glob(job['pid']+'.*')),'Orphan request trace; no implicit retry'
        pending[job['job_id']]=float(money(job['first_upper_cny'])+money(job['repair_upper_cny']))
    return pending

def ensure_pushed():
    assert not subprocess.check_output(['git','status','--porcelain'],cwd=REPO),'Commit preparation before live execution'
    env=dict(os.environ,GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='never')
    head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip()
    remote=subprocess.check_output(['git','ls-remote','origin','refs/heads/main'],cwd=REPO,text=True,env=env,timeout=30).split()[0]
    assert head==remote,'Source must be pushed before live calls'
    return head

def live(cfg,resume=False,review=None,authorization=''):
    from full_r8_report import report,finalize
    root=Path(cfg['campaign_root']);verify(root);plan=load(root/'study_plan.json')
    state=load(root/'study_state.json')
    old.support.no_other_runner(cfg)
    if (root/'active_run.json').exists():
        assert not old.support.registered_process_alive(load(root/'active_run.json')),'A live runner still owns this campaign'
    if resume:
        assert state['state']=='paused_for_api_review','Only the explicit review pause can be resumed'
        old_review=load(root/'review_authorization.json').get('review_ceiling_cny',REVIEW)
        assert review is not None and old_review<review<=TOTAL and authorization.strip(),'Explicit review continuation authorization required'
    else:
        assert state['state']=='prepared' and not (root/'active_run.json').exists(),'Study is not fresh'
        review=REVIEW
    head=ensure_pushed()
    catalog=old.credential_check(cfg)
    assert all(catalog['selected_models'].values()),'Required models missing'
    for backend in (old.support.CodesysBackend(cfg),old.support.OpenPLCBackend(cfg)):
        assert load(root/'native_preflight.json')[backend.name]['positive']['platform_identity']==backend.identity()
    before=(root/'ledger_before_study.json').read_bytes()
    assert hashlib.sha256(before).hexdigest()==plan['initial_ledger_sha256']
    if not resume:
        approved=migrate(cfg['budget_ledger_path'],before,sha(root/'study_plan.json'),stamp())
        atomic_json(root/'budget_authorization.json',approved)
        atomic_json(root/'run_environment.json',dict(published_preparation_commit=head,started_at=stamp(),catalog=catalog,
                    model_parameters=cfg['models'],review_pause_cny=REVIEW,automatic_retries=0))
        checkpoint(cfg,root)
    else:
        assert sha(cfg['budget_ledger_path'])==load(root/'ledger_checkpoint.json')['sha256'],'Ledger drifted during pause'
        atomic_json(root/'review_authorization.json',dict(previous_review_ceiling_cny=old_review,
                    review_ceiling_cny=review,user_authorization=authorization,at=stamp(),source_commit=head,
                    previous_authorization=load(root/'review_authorization.json')))
    budget=StudyBudget(cfg['budget_ledger_path'],sha(root/'study_plan.json'),review)
    history(cfg,root,plan)
    pending=remaining_jobs(root,plan)
    atomic_json(root/'active_run.json',dict(**old.support.current_process_marker(),state='running',entry='full_r8_study.py'))
    final_state='stopped';awake=False
    try:
        report(cfg,plan);publish()  # Publish authorization before the first paid call.
        if os.name=='nt':awake=bool(ctypes.windll.kernel32.SetThreadExecutionState(0x80000001))
        for job in plan['jobs']:
            if job['job_id'] not in pending:continue
            verify(root)
            assert sha(cfg['budget_ledger_path'])==load(root/'ledger_checkpoint.json')['sha256'],'Unrelated ledger mutation'
            history(cfg,root,plan)
            try:budget.admit_job(pending[job['job_id']])
            except ReviewPause as exc:
                final_state='paused_for_api_review'
                atomic_json(root/'study_state.json',dict(state=final_state,at=stamp(),next_job=job['job_id'],
                    reason=str(exc),review_ceiling_cny=review,remaining_jobs=list(pending)))
                break
            atomic_json(root/'study_state.json',dict(state='running',at=stamp(),current_job=job['job_id'],review_ceiling_cny=review))
            report(cfg,plan)
            record=generate_job(cfg,root,plan,job,budget,pending)
            assert record['job_done']
            snapshot=history(cfg,root,plan)
            assert snapshot['events'][-1]['status']=='settled'
            pending.pop(job['job_id']);checkpoint(cfg,root)
            summary=report(cfg,plan);publish()
            print('FINISHED',job['job_id'],'records',summary['recorded'],'increment',summary['study_increment_cny'],flush=True)
        else:
            final_state='completed'
            atomic_json(root/'study_state.json',dict(state=final_state,at=stamp(),review_ceiling_cny=review))
            s=report(cfg,plan);assert s['recorded']==140
            atomic_json(root/'completion.json',dict(completed=True,recorded=140,actual_requests=s['new_events'],
                        study_increment_cny=s['study_increment_cny'],total_accounted_cny=s['total_accounted_cny'],ended_at=stamp()))
    except BaseException as exc:
        atomic_json(root/'study_state.json',dict(state='stopped',at=stamp(),error=old.support.sanitize(str(exc))))
        raise
    finally:
        if awake:ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
        marker=load(root/'active_run.json');marker.update(state=final_state,ended_at=stamp())
        atomic_json(root/'active_run.json',marker)
        report(cfg,plan);publish()
    if final_state=='completed':
        finalize(cfg,plan)
        publish()
        print('COMPLETED AND AUDITED',flush=True)
    elif final_state=='paused_for_api_review':
        print('PAUSED FOR USER API REVIEW; no automatic resume',flush=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=('prepare','check','live','resume','serve','finalize'))
    parser.add_argument('--review-ceiling',type=float)
    parser.add_argument('--authorization',default='')
    parser.add_argument('--port',type=int,default=8883)
    args=parser.parse_args();cfg=config();root=Path(cfg['campaign_root'])
    if args.command=='prepare':prepare(cfg)
    elif args.command in ('live','resume'):live(cfg,args.command=='resume',args.review_ceiling,args.authorization)
    elif args.command=='serve':
        from full_r8_report import serve
        serve(cfg,args.port)
    elif args.command=='finalize':
        from full_r8_report import finalize
        finalize(cfg,load(root/'study_plan.json'))
    else:
        verify(root)
        if (root/'release_manifest.json').exists():
            from full_r8_report import audit_final
            audit_final(cfg,load(root/'study_plan.json'),released=True)
        print('PASS frozen full r8 study',flush=True)

if __name__=='__main__':main()

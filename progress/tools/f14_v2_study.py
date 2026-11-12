"""Independent Agent v2 study; frozen contract, one repair and no automatic retry."""
import argparse
from collections import Counter
from contextlib import ExitStack
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
from types import SimpleNamespace
sys.path.insert(0,str(Path(__file__).resolve().parent))
import full_r8b_study as old
from f14_v2_budget import KIND,TOTAL,REVIEW,BASELINE,HISTORY,StudyBudget,ReviewPause,authorize,prefix_ok
from full_r8b_transport import MeteredProvider
from stbench.billing import ledger_lock,money
from stbench.providers.base import ProviderError
from stbench.codex_baseline import ResponsesGateway
REPO=old.REPO
sys.path.insert(0,str(REPO/'progress/f14_agent_v2'))
sys.path.insert(0,str(REPO/'progress/f14_candidate'))
from codex_transport import InitialTextCodexProvider
from extraction import extract_code,SYSTEM
import f14_rotation_credentials as credentials
load,sha,stamp,atomic_json=old.load,old.sha,old.stamp,old.atomic_json
sanitize=old.old.support.sanitize
CONFIG=REPO/'progress/f14_agent_v2/config.json'
RELEASE=REPO/'progress/f14_agent_v2/release'
WORKER=REPO/'progress/f14_agent_v2/judge_worker.py'
MIRROR=REPO/'progress/evidence/f14_v2_20261112'

def config():
    cfg=load(CONFIG);previous=old.config()
    assert cfg['models']==previous['models'] and cfg['limits']==previous['limits']
    assert cfg['budget_cny']==TOTAL and cfg['system']==SYSTEM
    assert cfg['study']==dict(kind=KIND,total_cap_cny=TOTAL,review_pause_cny=None,max_requests=280,initial_spent_cny=BASELINE,initial_event_count=HISTORY,repair_input_bytes=65536)
    assert cfg['fifo_native_policy']=='unsupported_platform_keep_original_functional_and_formal'
    for key in ('budget_ledger_path','codesys_executable','codesys_profile','codesys_template'):assert cfg[key]==previous[key]
    return cfg

def tasks():
    rows={p.stem:load(p) for p in sorted(RELEASE.glob('datasets/*/*.json'))}
    assert len(rows)==35 and sum(len(p['test_cases']) for p in rows.values())==946
    return rows

def messages(job):
    return [dict(role='system',content=SYSTEM),dict(role='user',content=load(RELEASE/'agent_inputs.json')[job['pid']]['user'])]

def files():
    explicit=[Path(__file__),Path(__file__).with_name('f14_v2_budget.py'),Path(__file__).with_name('f14_v2_report.py'),
        Path(__file__).with_name('f14_v2_offline.py'),Path(__file__).with_name('f14_v2_replay.py'),
        Path(__file__).with_name('f14_v2_native_probe.py'),Path(__file__).with_name('f14_rotation_credentials.py'),
        CONFIG.parent/'runtime_probe.py',CONFIG.parent/'revision_manifest.json',CONFIG.parent/'codesys_probe_worker.py',
        CONFIG,CONFIG.parent/'实验方案.md',WORKER,REPO/'progress/tests/test_f14_v2.py',
        REPO/'progress/f14_candidate/codex_transport.py',REPO/'progress/f14_candidate/bridge.py',
        REPO/'progress/f14_candidate/judge_worker.py',REPO/'progress/f14_agent_v2/extraction.py',Path(old.__file__),Path(old.__file__).with_name('full_r8b_transport.py'),
        Path(old.__file__).with_name('full_r8b_http_worker.py'),
        Path(old.__file__).with_name('f14_study.py'),Path(old.__file__).with_name('f14_study_budget.py'),
        Path(old.__file__).with_name('full_r8b_budget.py'),CONFIG.parent/'README.md']
    runtime=list((REPO/'agent_dev_r9_stage3/stbench').rglob('*.py'))
    return sorted(set(explicit+runtime))

def build_plan(cfg,before):
    routes=load(Path(cfg['campaign_root'])/'offline_routes.json');bounds={r['job_id']:r for r in routes['rows']};work=[]
    for n,pid in enumerate(tasks()):
        for i in old.ORDERS[n%4]:
            framework,modelid=old.ARMS[i];condition=framework+'_'+modelid;job_id=condition+'/'+pid
            work.append(dict(pid=pid,framework=framework,model_id=modelid,condition=condition,job_id=job_id,
                first_upper_cny=bounds[job_id]['first_upper_cny'],repair_upper_cny=bounds[job_id]['repair_upper_cny'],
                initial_user_sha256=hashlib.sha256(messages(dict(pid=pid))[1]['content'].encode()).hexdigest()))
    assert len(work)==len({j['job_id'] for j in work})==140 and routes['completed']
    upper=sum((money(j['first_upper_cny'])+money(j['repair_upper_cny']) for j in work),money(0))
    assert money(before['spent_cny'])+upper<=money(TOTAL),'Full coverage must fit before live authorization'
    return dict(kind=KIND,jobs=work,planned=140,maximum_requests=280,initial_spent_cny=BASELINE,initial_event_count=HISTORY,
        total_cap_cny=TOTAL,review_pause_cny=None,worst_reservation_cny=float(upper),initial_ledger_sha256=sha(cfg['budget_ledger_path']),
        files={p.relative_to(REPO).as_posix():sha(p) for p in files()},
        release_files={p.relative_to(RELEASE).as_posix():sha(p) for p in RELEASE.rglob('*') if p.is_file()},
        cli_identity=old.old.cli_identity(),native_identity=old.old.support.CodesysBackend(cfg).identity(),
        fifo_native_policy=cfg['fifo_native_policy'],native_eligible_tasks=34,original_tasks=35,cases_per_arm=946,
        old_paid_plan_sha256=sha(Path(old.config()['campaign_root'])/'study_plan.json'),
        old_paid_package_sha256=sha(Path(old.config()['campaign_root'])/'验收包.zip'),
        offline_routes_sha256=sha(Path(cfg['campaign_root'])/'offline_routes.json'),
        diagnostic_files={p.relative_to(CONFIG.parent).as_posix():sha(p) for p in (CONFIG.parent/'diagnostics').rglob('*') if p.is_file()},
        secondary_cipher_sha256=sha(cfg['credential_rotation']['secondary_dpapi_path']),
        previous_f14_audit_sha256=sha(REPO/'progress/evidence/f14_p1_20261111b/final_audit.json'))

def verify(cfg):
    root=Path(cfg['campaign_root']);plan=load(root/'study_plan.json');prepared=load(root/'prepared.json')
    assert sha(root/'study_plan.json')==prepared['plan_sha256'] and sha(root/'validation.json')==prepared['validation_sha256']
    assert plan['files']=={p.relative_to(REPO).as_posix():sha(p) for p in files()},'Study source/config changed'
    assert plan['release_files']=={p.relative_to(RELEASE).as_posix():sha(p) for p in RELEASE.rglob('*') if p.is_file()}
    assert old.old.cli_identity()==plan['cli_identity'] and old.old.support.CodesysBackend(cfg).identity()==plan['native_identity']
    # Historical snapshots stay unchanged; the installed CLI is independently frozen for v2.
    assert sha(Path(old.config()['campaign_root'])/'study_plan.json')==plan['old_paid_plan_sha256']
    assert sha(Path(old.config()['campaign_root'])/'验收包.zip')==plan['old_paid_package_sha256']
    assert sha(cfg['credential_rotation']['secondary_dpapi_path'])==plan['secondary_cipher_sha256']
    assert sha(REPO/'progress/evidence/f14_p1_20261111b/final_audit.json')==plan['previous_f14_audit_sha256']
    assert sha(root/'offline_routes.json')==plan['offline_routes_sha256']
    assert plan['diagnostic_files']=={p.relative_to(CONFIG.parent).as_posix():sha(p) for p in (CONFIG.parent/'diagnostics').rglob('*') if p.is_file()}
    return plan

def history(cfg,root,plan):
    state=load(cfg['budget_ledger_path']);before=load(root/'ledger_before_study.json')
    assert prefix_ok(state,before),'Historic events/recoveries/authorizations changed'
    new=state['events'][HISTORY:];assert len(new)<=280
    keys=[(e.get('request',{}).get('job_id'),e.get('request',{}).get('candidate_index')) for e in new]
    assert len(keys)==len(set(keys)) and all(i in (0,1) for _,i in keys),'Duplicate or third candidate'
    allowed={j['job_id'] for j in plan['jobs']}
    assert all(e['phase']==KIND and e['request']['job_id'] in allowed for e in new)
    accounted=sum((money(e.get('accounted_cny',e['reserved_cny'])) for e in new),money(BASELINE))
    assert accounted==money(state['spent_cny']) and accounted<=money(TOTAL)
    return state

def remaining(root,plan):
    pending={}
    for job in plan['jobs']:
        folder=root/'jobs'/job['condition'];record=load(folder/(job['pid']+'.json'))
        if record:
            assert record.get('job_done'),'Partial job requires inspection; never repeat its request'
            continue
        assert not list(folder.glob(job['pid']+'.*')),'Orphan request/evidence; do not retry'
        pending[job['job_id']]=float(money(job['first_upper_cny'])+money(job['repair_upper_cny']))
    return pending

def run_stage(source,pid,mode,remaining_seconds):
    timeout=min(38 if mode=='bounded' else 30,remaining_seconds)
    if timeout<=0:raise RuntimeError('Task deadline reached before evaluation stage')
    env=dict(os.environ,PYTHONUTF8='1',PYTHONDONTWRITEBYTECODE='1')
    for key in ('DMXAPI_API_KEY','F14_DMXAPI_SECONDARY_KEY','OPENAI_API_KEY','ANTHROPIC_API_KEY'):env.pop(key,None)
    seconds=min(30,max(.1,timeout-8))
    process=subprocess.run([sys.executable,'-B','-X','utf8',str(WORKER)],
        input=json.dumps(dict(source=source,pid=pid,mode=mode,seconds=seconds)),capture_output=True,
        text=True,encoding='utf-8',env=env,cwd=WORKER.parent,timeout=timeout,
        creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
    if process.returncode:raise RuntimeError('Isolated F1.4 worker failed: '+sanitize(process.stderr[-1000:]))
    return json.loads(process.stdout)

def evaluate(source,pid,cfg,deadline):
    static=run_stage(source,pid,'static',deadline-time.monotonic())
    native=dict(platform='codesys',status='not_run',diagnostics=['Static/interface gate did not pass'])
    import re
    complete_fb=bool(re.search(r'\bFUNCTION_BLOCK\s+\w+',source,re.I) and re.search(r'\bEND_FUNCTION_BLOCK\b',source,re.I))
    if static['result']['compiles'] or complete_fb:
        if pid=='public-hard-04':
            native=dict(platform='codesys',status='unsupported_platform',diagnostics=['Course-original VARIANT interface is unsupported on this CODESYS profile; separate DINT results excluded'])
        else:
            backend=old.old.support.CodesysBackend(cfg);backend.timeout=min(120,max(.01,deadline-time.monotonic()))
            native=backend.compile(source,SimpleNamespace(pid=pid)).to_dict()
        if native['status'] in ('passed','unsupported_platform'):
            errors=static['result'].get('compile_errors',[])
            interface_error=any(e.get('code','').startswith(('E_INTERFACE','E_POU_KIND')) for e in errors)
            if not static['result']['compiles']:
                result=copy.deepcopy(static)
                if not interface_error and native['status']=='passed':
                    result['result'].update(compiles=True,compile_errors=[],mc_error='Unsupported modeling: native compiler accepted code outside local checker subset')
                    result['result']['evidence_metadata'].update(classification='unsupported_modeling',local_checker_errors=errors)
                    result['verification_status']='inconclusive'
                    result['feedback']='CODESYS compilation passed. Local checker cannot evaluate this syntax; no model repair is requested.'
            else:result=run_stage(source,pid,'functional',deadline-time.monotonic())
            if result['result']['compiles'] and result['result']['tests_passed']==result['result']['tests_total'] and result['verification_status']!='inconclusive':
                if deadline-time.monotonic()>9:
                    result=run_stage(source,pid,'bounded',deadline-time.monotonic())
                else:result['feedback']+='\nFormal stage not executed: insufficient remaining task time.'
        else:result=static
    else:result=static
    result['result']['platform_results']={'codesys':native}
    result['complete_code']=static['complete_code'] or (complete_fb and native['status']=='passed')
    if native['status'] not in ('passed','not_run','unsupported_platform'):
        result['feedback']='CODESYS native compilation: '+native['status']+'\n'+'\n'.join(native.get('diagnostics',[])[:8])+'\n'+result['feedback']
    result['shared_tool_error']=native['status'] in ('timeout','tool_error','unavailable') or result['verification_status']=='tool_error'
    return result

def classify(evaluation):
    r=evaluation['result'];native=r.get('platform_results',{}).get('codesys',{}).get('status','not_run')
    passed=r['compiles'] and r['tests_total']>0 and r['tests_passed']==r['tests_total']
    return dict(complete_code=evaluation.get('complete_code',False),compiles=r['compiles'],native_pass=native=='passed',
        native_eligible=native!='unsupported_platform',functional_pass=bool(passed),tests_passed=r['tests_passed'],tests_total=r['tests_total'],
        verification_status=evaluation['verification_status'],judge=r,feedback=evaluation['feedback'])

def repairable(a):
    if a['judge'].get('evidence_metadata',{}).get('classification')=='unsupported_modeling':return False
    if a['verification_status'] in ('tool_error',):return False
    native=a['judge'].get('platform_results',{}).get('codesys',{}).get('status','not_run')
    if native in ('timeout','tool_error','unavailable'):return False
    if a['verification_status']=='violated':return True
    if a['functional_pass'] and native in ('passed','unsupported_platform'):return False
    return bool(a['judge'].get('compile_errors')) or native=='failed' or (a['compiles'] and not a['functional_pass'])

def select_best(attempts):
    def score(a):
        usable=a['functional_pass'] and (a['native_pass'] or not a['native_eligible'])
        return (usable and a['verification_status'] in ('bounded_pass','not_applicable'),usable,a['native_pass'],a['compiles'],a['tests_passed'],a['verification_status']!='violated',-a['idx'])
    return max(range(len(attempts)),key=lambda i:score(attempts[i])) if attempts else None

def capture(transport,budget,job,idx,pending,folder,root):
    count=[0];lock=threading.Lock()
    transport.diagnostic_dir=root/'transport_private'/job['condition']/job['pid']/str(idx)
    def before(actual):
        with lock:
            if count[0]:raise ProviderError('One upstream request per candidate; retries forbidden')
            bound=money(job['first_upper_cny'] if idx==0 else job['repair_upper_cny'])
            if money(transport.upper(actual))>bound:raise ProviderError('Frozen input bound exceeded before send')
            protected=sum((money(v) for k,v in pending.items() if k!=job['job_id']),money(0))
            budget.protected_cny=float(protected+(money(job['repair_upper_cny']) if idx==0 else money(0)))
            budget.context=dict(job_id=job['job_id'],candidate_index=idx,study_kind=KIND)
            path=folder/(job['pid']+f'.request_{idx+1:02}.json')
            if path.exists():raise ProviderError('Existing request trace; no retry')
            if idx==0 and not any(m['role']=='user' and hashlib.sha256(m['content'].encode()).hexdigest()==job['initial_user_sha256'] for m in actual):
                raise ProviderError('Initial course user text changed')
            payload=dict(model=transport.model,protocol=transport.protocol,max_output_tokens=16384,timeout_seconds=420,
                parameters=transport.spec.get('parameters',{}),messages=actual)
            raw=json.dumps(payload,ensure_ascii=False);assert sanitize(raw)==raw,'Credential in public request evidence'
            atomic_json(path,payload);count[0]+=1
    def observe(raw,protocol):
        atomic_json(folder/(job['pid']+f'.response_{idx+1:02}.json'),json.loads(sanitize(json.dumps(dict(protocol=protocol,raw_response=raw),ensure_ascii=False))))
    original=transport.original_sender if hasattr(transport,'original_sender') else transport.sender
    transport.original_sender=original
    def sender(*args):
        try:raw=original(*args);observe(raw,transport.protocol);return raw
        finally:
            path=transport.diagnostic_dir/'diagnostic.json'
            if path.exists():atomic_json(folder/(job['pid']+f'.transport_{idx+1:02}.json'),json.loads(sanitize(path.read_text(encoding='utf-8'))))
    transport.sender=sender;transport.before_send=before;transport.response_observer=observe
    return count

def generate_job(cfg,root,plan,job,budget,pending,*,factory=MeteredProvider,evaluator=evaluate):
    folder=root/'jobs'/job['condition'];folder.mkdir(parents=True,exist_ok=True)
    assert not list(folder.glob(job['pid']+'.*')),'Existing job evidence; no implicit replay'
    path=folder/(job['pid']+'.json');model=next(m for m in cfg['models'] if m['id']==job['model_id'])
    started=time.monotonic();deadline=started+1200;current=messages(job);fatal=None
    record=dict(job_id=job['job_id'],pid=job['pid'],condition=job['condition'],model=model['model'],
        experiment_kind='live',credential_batch='secondary',job_done=False,attempts=[],best_attempt=None,stop_reason='',tests_total=len(tasks()[job['pid']]['test_cases']),
        study_plan_sha256=sha(root/'study_plan.json'),started_at=stamp())
    def save():
        record.update(best_attempt=select_best(record['attempts']),wall_seconds=round(time.monotonic()-started,6),finished_at=stamp())
        atomic_json(path,record)
    try:
        with ExitStack() as stack:
            transport=factory(model,budget,max_tokens=16384,protocol=model['generation_protocol'],timeout=420)
            provider=transport
            if job['framework']=='codex':
                gateway=stack.enter_context(ResponsesGateway(provider=transport,model=transport.model))
                provider=InitialTextCodexProvider(gateway,model=transport.model,work_root=root/'cli_private',timeout=65 if transport.offline else 451)
            for idx in range(2):
                if deadline-time.monotonic()<451:record.update(job_done=True,stop_reason='insufficient_request_window');break
                capture(transport,budget,job,idx,pending,folder,root)
                call_started=time.monotonic()
                try:
                    response=provider.generate(current);source=extract_code(response.text);digest=hashlib.sha256(source.encode()).hexdigest()
                    (folder/(job['pid']+f'.candidate_{idx+1:02}.st')).write_bytes(source.encode())
                    if idx and digest==record['attempts'][0]['code_hash']:
                        attempt=copy.deepcopy(record['attempts'][0]);attempt['idx']=idx
                        record.update(job_done=True,stop_reason='repeated_candidate')
                    else:
                        result=evaluator(source,job['pid'],cfg,deadline);attempt=classify(result);attempt.update(idx=idx,code=source,code_hash=digest)
                        if result.get('shared_tool_error'):fatal=RuntimeError('Shared evaluation tool failure');record['stop_reason']='shared_tool_error'
                        elif not repairable(attempt):record.update(job_done=True,stop_reason='functional_pass_formal_'+attempt['verification_status'] if attempt['functional_pass'] else 'not_repairable')
                        elif idx==1:record.update(job_done=True,stop_reason='maximum_two_candidates')
                    attempt.update(actual_model=response.model,prompt_tokens=response.usage['prompt_tokens'],completion_tokens=response.usage['completion_tokens'],
                        cost_cny=response.cost_cny,latency_s=round(time.monotonic()-call_started,6),provider_error='')
                    record['attempts'].append(attempt)
                    if fatal or record['job_done']:break
                    current=messages(job)+[dict(role='assistant',content=source),dict(role='user',content=attempt['feedback'][:4000]+'\n修复并返回完整代码，保持题面接口。')]
                except ProviderError as exc:
                    error=sanitize(str(exc));known=error.startswith('Generation incomplete/empty:');receipt=transport.last_receipt
                    record['attempts'].append(dict(idx=idx,code='',code_hash='',complete_code=False,compiles=False,native_pass=False,
                        native_eligible=job['pid']!='public-hard-04',functional_pass=False,tests_passed=0,tests_total=record['tests_total'],
                        verification_status='not_run',judge={},feedback='',provider_error=error,actual_model=receipt.get('model',''),
                        prompt_tokens=receipt.get('prompt_tokens',0),completion_tokens=receipt.get('completion_tokens',0),
                        cost_cny=transport.last_charge,latency_s=round(time.monotonic()-call_started,6)))
                    record.update(job_done=known,stop_reason='generation_incomplete' if known else 'provider_error',error=error)
                    if not known:fatal=exc
                    break
                finally:save()
    finally:save()
    if fatal:raise fatal
    return record

def publish():
    assert not subprocess.check_output(['git','diff','--cached','--name-only'],cwd=REPO),'Unrelated staged changes'
    for p in MIRROR.rglob('*'):
        if p.is_file() and p.suffix!='.zip':assert sanitize(p.read_text(encoding='utf-8'))==p.read_text(encoding='utf-8')
    subprocess.run(['git','add','--',MIRROR.relative_to(REPO).as_posix()],cwd=REPO,check=True,capture_output=True)
    if subprocess.run(['git','diff','--cached','--quiet'],cwd=REPO).returncode:
        subprocess.run(['git','commit','-q','-m','chore: archive independent F1.4 experiment progress'],cwd=REPO,check=True,capture_output=True)
    env=dict(os.environ,GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='never')
    subprocess.run(['git','-c','http.version=HTTP/1.1','-c','http.lowSpeedLimit=1000','-c','http.lowSpeedTime=30','push','origin','main'],
        cwd=REPO,env=env,check=True,capture_output=True,timeout=60)

def checkpoint(cfg,root):
    state=load(cfg['budget_ledger_path'])
    atomic_json(root/'ledger_checkpoint.json',dict(sha256=sha(cfg['budget_ledger_path']),events=len(state['events']),spent_cny=state['spent_cny'],at=stamp()))

def audit_final(cfg,root,plan):
    state=history(cfg,root,plan);events=state['events'][HISTORY:]
    linked={(e['request']['job_id'],e['request']['candidate_index']):e for e in events}
    attempts=0
    for job in plan['jobs']:
        folder=root/'jobs'/job['condition'];record=load(folder/(job['pid']+'.json'))
        assert record['job_done'] and record['job_id']==job['job_id'] and 1<=len(record['attempts'])<=2
        assert record['study_plan_sha256']==sha(root/'study_plan.json') and record['best_attempt']==select_best(record['attempts'])
        for index,attempt in enumerate(record['attempts']):
            assert attempt['idx']==index
            event=linked[(job['job_id'],index)];assert event['status']=='settled'
            assert money(attempt['cost_cny'])==money(event['accounted_cny'])
            assert attempt['actual_model']==event['metadata']['model']
            for field in ('prompt_tokens','completion_tokens'):assert attempt[field]==event['metadata'][field]
            assert (folder/(job['pid']+f'.request_{index+1:02}.json')).is_file()
            assert (folder/(job['pid']+f'.response_{index+1:02}.json')).is_file()
            if attempt['code']:
                assert hashlib.sha256(attempt['code'].encode()).hexdigest()==attempt['code_hash']
                assert (folder/(job['pid']+f'.candidate_{index+1:02}.st')).read_bytes()==attempt['code'].encode()
            attempts+=1
    assert attempts==len(events)<=280
    return dict(passed=True,original_events_preserved=True,jobs=140,attempts=attempts,cases_per_arm=946,
        native_eligible_per_arm=34,fifo_native_platform_unsupported=True,ledger_sha256=sha(cfg['budget_ledger_path']),
        study_plan_sha256=sha(root/'study_plan.json'),at=stamp())

def prepare(cfg):
    from f14_v2_report import report
    root=Path(cfg['campaign_root']);assert root.is_dir() and not (root/'prepared.json').exists(),'Prepared study cannot be overwritten'
    old.old.support.no_other_runner(cfg)
    before=Path(cfg['budget_ledger_path']).read_bytes();state=json.loads(before)
    assert (state['spent_cny'],len(state['events']),state['limit_cny'],bool(state.get('halted')))==(BASELINE,HISTORY,190,False)
    plan=build_plan(cfg,state)
    logpath=root/('free_tests_'+str(time.time_ns())+'.log')
    with logpath.open('xb') as log:
        proc=subprocess.run([sys.executable,'-B','-X','utf8','-m','unittest','discover','-s','progress/tests','-p','test_f14_v2.py','-v'],cwd=REPO,stdout=log,stderr=log,timeout=300)
    test_log=logpath.read_text(encoding='utf-8')
    assert proc.returncode==0,test_log[-2200:]
    assert Path(cfg['budget_ledger_path']).read_bytes()==before
    assert not (root/'ledger_before_study.json').exists();(root/'ledger_before_study.json').write_bytes(before)
    (root/'free_tests.log').write_text(test_log,encoding='utf-8')
    atomic_json(root/'study_plan.json',plan)
    routes=load(root/'offline_routes.json')
    atomic_json(root/'validation.json',dict(passed=True,tests=test_log,initial_fake_routes=140,repair_fake_routes=routes['repair_fake_routes'],
        native_original_passed=32,reference_patches_passed=2,native_fifo_supported=False,reference_functional_cases=946,
        external_requests=0,ledger_unchanged=True))
    atomic_json(root/'prepared.json',dict(plan_sha256=sha(root/'study_plan.json'),validation_sha256=sha(root/'validation.json')))
    atomic_json(root/'study_state.json',dict(state='prepared',at=stamp()));report(cfg,plan)
    print('PREPARED 140 tasks; worst reserve',plan['worst_reservation_cny'],'CNY; total',float(money(BASELINE)+money(plan['worst_reservation_cny'])),flush=True)

def live(cfg,resume=False):
    from f14_v2_report import report
    root=Path(cfg['campaign_root']);plan=verify(cfg);old.old.support.no_other_runner(cfg)
    state=load(root/'study_state.json')
    permission=load(root/'user_budget_approval.json')
    assert permission.get('approved_total_cap_cny')==TOTAL and permission.get('study_plan_sha256')==sha(root/'study_plan.json'),'Do not change ledger or send paid requests without matching explicit cap authorization'
    assert state['state'] in (('stopped','running') if resume else ('prepared',))
    head=old.ensure_pushed();binding=credentials.load_credentials(cfg);catalog=credentials.catalog(cfg,'secondary')
    before=(root/'ledger_before_study.json').read_bytes();assert hashlib.sha256(before).hexdigest()==plan['initial_ledger_sha256']
    if not resume:
        approval=authorize(cfg['budget_ledger_path'],before,sha(root/'study_plan.json'),stamp(),sha(root/'user_budget_approval.json'))
        atomic_json(root/'budget_authorization.json',approval)
        atomic_json(root/'run_environment.json',dict(published_preparation_commit=head,started_at=stamp(),catalog=catalog,
            maximum_requests=280,automatic_retries=0,model_parameters=cfg['models'],user_permission_sha256=sha(root/'user_budget_approval.json')))
        atomic_json(root/'current_credential_batch.json',dict(slot='secondary',key_sha256=binding['secondary']))
        atomic_json(root/'credential_batches/secondary.json',dict(slot='secondary',key_sha256=binding['secondary'],catalog=catalog,at=stamp()))
        checkpoint(cfg,root)
    else:assert sha(cfg['budget_ledger_path'])==load(root/'ledger_checkpoint.json')['sha256'],'Ledger changed since checkpoint'
    assert sha(root/'user_budget_approval.json')==load(root/'run_environment.json')['user_permission_sha256']
    assert load(root/'current_credential_batch.json')['key_sha256']==binding['secondary'],'Credential changed: independent batch required'
    budget=StudyBudget(cfg['budget_ledger_path'],sha(root/'study_plan.json'));history(cfg,root,plan);pending=remaining(root,plan)
    final='stopped';awake=False
    atomic_json(root/'active_run.json',dict(**old.old.support.current_process_marker(),state='running',entry='f14_v2_study.py'))
    try:
        report(cfg,plan);publish()
        if os.name=='nt':awake=bool(ctypes.windll.kernel32.SetThreadExecutionState(0x80000001))
        for job in plan['jobs']:
            if job['job_id'] not in pending:continue
            verify(cfg);assert sha(cfg['budget_ledger_path'])==load(root/'ledger_checkpoint.json')['sha256'],'Unrelated ledger mutation'
            history(cfg,root,plan)
            try:budget.admit_job(pending[job['job_id']])
            except ReviewPause as exc:
                final='paused_for_api_review';atomic_json(root/'study_state.json',dict(state=final,at=stamp(),reason=str(exc),next_job=job['job_id'],remaining_jobs=list(pending)));break
            atomic_json(root/'study_state.json',dict(state='running',at=stamp(),current_job=job['job_id']));report(cfg,plan)
            result=generate_job(cfg,root,plan,job,budget,pending,factory=credentials.provider_factory);assert result['job_done']
            state=history(cfg,root,plan);assert state['events'][-1]['status']=='settled'
            pending.pop(job['job_id']);checkpoint(cfg,root);summary=report(cfg,plan);publish()
            print('FINISHED',job['job_id'],summary['recorded'],'/140',state['spent_cny'],'CNY',flush=True)
        else:
            final='completed';assert len([p for p in (root/'jobs').rglob('*.json') if p.name.count('.')==1])==140
            atomic_json(root/'final_audit.json',audit_final(cfg,root,plan))
            atomic_json(root/'study_state.json',dict(state=final,at=stamp()))
            atomic_json(root/'completion.json',dict(completed=True,recorded=140,actual_requests=len(state['events'])-HISTORY,
                total_accounted_cny=state['spent_cny'],ended_at=stamp()))
    except BaseException as exc:
        atomic_json(root/'study_state.json',dict(state='stopped',at=stamp(),error=sanitize(type(exc).__name__+': '+str(exc))));raise
    finally:
        if awake:ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
        marker=load(root/'active_run.json');marker.update(state=final,ended_at=stamp());atomic_json(root/'active_run.json',marker)
        checkpoint(cfg,root);report(cfg,plan);publish()

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('command',choices=('prepare','check','live','resume','serve'))
    parser.add_argument('--port',type=int,default=8886);args=parser.parse_args();cfg=config()
    if args.command=='prepare':prepare(cfg)
    elif args.command=='check':verify(cfg);history(cfg,Path(cfg['campaign_root']),load(Path(cfg['campaign_root'])/'study_plan.json'));print('PASS frozen F1.4 study and ledger history')
    elif args.command=='serve':
        from f14_v2_report import serve
        serve(cfg,args.port)
    else:live(cfg,args.command=='resume')

if __name__=='__main__':main()

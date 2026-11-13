"""Independent Agent v2 study; frozen contract, up to three repairs and no automatic retry."""
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
from f14_v10_budget import KIND,TOTAL,BASELINE,HISTORY,Coordinator,CampaignStopped,authorize
REVIEW=None
def prefix_ok(state,before):
    return (state['events'][:len(before['events'])]==before['events']
        and state.get('recoveries',[])[:len(before.get('recoveries',[]))]==before.get('recoveries',[])
        and all(state.get(k)==v for k,v in before.items() if k.endswith('_authorization')))
from full_r8b_transport import MeteredProvider
from stbench.billing import ledger_lock,money
from stbench.providers.base import ProviderError
from stbench.codex_baseline import ResponsesGateway
REPO=old.REPO
sys.path.insert(0,str(REPO/'progress/f14_agent_v10'))
sys.path.insert(0,str(REPO/'progress/f14_candidate'))
from codex_transport import InitialTextCodexProvider
from v10_extraction import extract_code,SYSTEM
from v10_formatting import normalize
API_SEMAPHORES={key:threading.Semaphore(4) for key in ("deepseek-v4pro","minimax-m27")}
NATIVE_LOCK=threading.Lock()
FORMAL_SEMAPHORE=threading.Semaphore(2)
import f14_rotation_credentials as credentials
load,sha,stamp=old.load,old.sha,old.stamp
from f14_v10_io import atomic_json
sanitize=old.old.support.sanitize
CONFIG=REPO/'progress/f14_agent_v10/config.json'
RELEASE=REPO/'progress/f14_agent_v10/release'
WORKER=REPO/'progress/f14_agent_v10/judge_worker.py'
MIRROR=REPO/'progress/evidence/f14_v10_full_20261113'

def config():
    cfg=load(CONFIG);previous=old.config()
    expected_limits=dict(previous['limits'],max_candidates=4,task_seconds=2400)
    assert cfg['models']==previous['models'] and cfg['limits']==expected_limits
    assert cfg['budget_cny']==TOTAL and cfg['system']==SYSTEM
    assert cfg['study']==dict(kind=KIND,total_cap_cny=TOTAL,review_pause_cny=None,max_requests=560,initial_spent_cny=BASELINE,initial_event_count=HISTORY,repair_input_bytes=65536,codex_repair_input_bytes=90112)
    assert cfg['fifo_native_policy']=='unsupported_platform_keep_original_functional_and_formal'
    for key in ('budget_ledger_path','codesys_executable','codesys_profile','codesys_template'):assert cfg[key]==previous[key]
    return cfg

def all_tasks():
    rows={p.stem:load(p) for p in sorted(RELEASE.glob('datasets/*/*.json'))}
    assert len(rows)==35 and sum(len(p['test_cases']) for p in rows.values())==946
    return rows

from v10_contracts import PIDS, clauses, clause_index, compliance

def tasks():
    return all_tasks()

def messages(job):
    interface=[{key:v[key] for key in ('name','data_type','direction','fields') if key in v} for v in tasks()[job['pid']]['variables']]
    contract=SYSTEM+'\nCanonical interface declarations (from task interface only, not a solution):\n'+json.dumps(interface,ensure_ascii=False)
    user=load(RELEASE/'agent_inputs.json')[job['pid']]['user']
    contract+='\nPublic requirement citation index into the complete unchanged user message (zero-based Unicode character positions, end exclusive; read the actual text there):\n'+json.dumps(clause_index(user),ensure_ascii=False)
    from public_time_bounds import derive
    contract+='\nPublic-text discrete-time boundary arithmetic (not test data):\n'+json.dumps(derive(user),ensure_ascii=False)
    return [dict(role='system',content=contract),dict(role='user',content=user)]

def files():
    import f14_v6_core as prior
    root=REPO/'progress/f14_agent_v10'
    own=[p for p in root.rglob('*') if p.is_file() and 'release' not in p.relative_to(root).parts and '__pycache__' not in p.parts]
    own += [Path(__file__).with_name('f14_v10_'+name+'.py') for name in ('core','budget','study','report','offline','preflight','review','dashboard','repair_probe','io','resume_recovery')]
    own += sorted((REPO/'progress/tests').glob('test_f14_v10*.py'))
    return sorted(set(prior.files()+own))


def build_plan(cfg,before):
    routes=load(Path(cfg['campaign_root'])/'offline_routes.json');bounds={r['job_id']:r for r in routes['rows']};work=[]
    for n,pid in enumerate(tasks()):
        for i in old.ORDERS[n%4]:
            framework,modelid=old.ARMS[i];condition=framework+'_'+modelid;job_id=condition+'/'+pid
            work.append(dict(pid=pid,framework=framework,model_id=modelid,condition=condition,job_id=job_id,
                first_upper_cny=bounds[job_id]['first_upper_cny'],repair_upper_cny=bounds[job_id]['repair_upper_cny'],
                initial_user_sha256=hashlib.sha256(messages(dict(pid=pid))[1]['content'].encode()).hexdigest()))
    assert len(work)==len({j['job_id'] for j in work})==140 and routes['completed']
    upper=sum((money(j['first_upper_cny'])+3*money(j['repair_upper_cny']) for j in work),money(0))
    assert money(before['spent_cny'])+upper<=money(TOTAL),'Full coverage must fit before live authorization'
    return dict(kind=KIND,jobs=work,planned=140,maximum_requests=560,maximum_candidates_per_job=4,task_seconds=2400,initial_spent_cny=BASELINE,initial_event_count=HISTORY,
        total_cap_cny=TOTAL,review_pause_cny=None,worst_reservation_cny=float(upper),initial_ledger_sha256=sha(cfg['budget_ledger_path']),
        files={p.relative_to(REPO).as_posix():sha(p) for p in files()},
        release_files={p.relative_to(RELEASE).as_posix():sha(p) for p in RELEASE.rglob('*') if p.is_file()},
        cli_identity=old.old.cli_identity(),native_identity=old.old.support.CodesysBackend(cfg).identity(),
        fifo_native_policy=cfg['fifo_native_policy'],native_eligible_tasks=34,original_tasks=35,cases_per_arm=sum(len(p['test_cases']) for p in tasks().values()),
        old_paid_plan_sha256=sha(Path(old.config()['campaign_root'])/'study_plan.json'),
        old_paid_package_sha256=sha(Path(old.config()['campaign_root'])/'验收包.zip'),
        offline_routes_sha256=sha(Path(cfg['campaign_root'])/'offline_routes.json'),
        offline_repair_routes_sha256=sha(Path(cfg['campaign_root'])/'offline_repair_routes.json'),
        budget_refinement_sha256=sha(Path(cfg['campaign_root'])/'budget_refinement.json'),
        diagnostic_files={p.relative_to(REPO).as_posix():sha(p) for p in (REPO/'progress/evidence/f14_v10_preflight_20261113').rglob('*') if p.is_file()},
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
    assert sha(root/'offline_repair_routes.json')==plan['offline_repair_routes_sha256']
    assert sha(root/'budget_refinement.json')==plan['budget_refinement_sha256']
    assert plan['diagnostic_files']=={p.relative_to(REPO).as_posix():sha(p) for p in (REPO/'progress/evidence/f14_v10_preflight_20261113').rglob('*') if p.is_file()}
    return plan

def old_history_unused(cfg,root,plan):
    state=load(cfg['budget_ledger_path']);before=load(root/'ledger_before_study.json')
    assert prefix_ok(state,before),'Historic events/recoveries/authorizations changed'
    new=state['events'][HISTORY:];assert len(new)<=560
    keys=[(e.get('request',{}).get('job_id'),e.get('request',{}).get('candidate_index')) for e in new]
    assert len(keys)==len(set(keys)) and all(i in range(4) for _,i in keys),'Duplicate or third candidate'
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
        pending[job['job_id']]=float(money(job['first_upper_cny'])+3*money(job['repair_upper_cny']))
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
    timing={}
    def stage(mode):
        started=time.monotonic();result=run_stage(source,pid,mode,deadline-time.monotonic())
        timing[mode+'_seconds']=round(time.monotonic()-started,6);return result
    static=stage('static')
    native=dict(platform='codesys',status='not_run',diagnostics=['Static/interface gate did not pass'])
    import re
    complete_fb=bool(re.search(r'\bFUNCTION_BLOCK\s+\w+',source,re.I) and re.search(r'\bEND_FUNCTION_BLOCK\b',source,re.I))
    if static['result']['compiles'] or complete_fb:
        if pid=='public-hard-04':
            native=dict(platform='codesys',status='unsupported_platform',diagnostics=['Course-original VARIANT interface is unsupported on this CODESYS profile; separate DINT results excluded'])
        else:
            queue=time.monotonic()
            with NATIVE_LOCK:
                timing['native_queue_seconds']=round(time.monotonic()-queue,6)
                backend=old.old.support.CodesysBackend(cfg);backend.timeout=min(120,max(.01,deadline-time.monotonic()))
                started=time.monotonic();native=backend.compile(source,SimpleNamespace(pid=pid)).to_dict()
                timing['native_compile_seconds']=round(time.monotonic()-started,6)
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
            else:result=stage('functional')
            if result['result']['compiles'] and result['result']['tests_passed']==result['result']['tests_total'] and result['verification_status']!='inconclusive':
                if deadline-time.monotonic()>9:
                    queue=time.monotonic()
                    with FORMAL_SEMAPHORE:
                        timing['formal_queue_seconds']=round(time.monotonic()-queue,6)
                        contract_report=result['result'].get('evidence_metadata',{}).get('declared_contract_check')
                        result=stage('bounded')
                        if contract_report is not None:result['result'].setdefault('evidence_metadata',{})['declared_contract_check']=contract_report
                else:result['feedback']+='\nFormal stage not executed: insufficient remaining task time.'
        else:result=static
    else:result=static
    result['result']['platform_results']={'codesys':native}
    result['complete_code']=static['complete_code'] or (complete_fb and native['status']=='passed')
    if native['status'] not in ('passed','not_run','unsupported_platform'):
        diagnostics=native.get('diagnostics',[])
        errors=[line for line in diagnostics if re.search(r'\berror\b|\bC\d{4}\b',line,re.I)]
        result['feedback']='CODESYS native compilation: '+native['status']+'\n'+'\n'.join((errors or diagnostics)[:8])+'\n'+result['feedback']
    result['timing']=timing
    result['shared_tool_error']=native['status'] in ('timeout','tool_error','unavailable') or result['verification_status']=='tool_error'
    return result

def classify(evaluation):
    r=evaluation['result'];native=r.get('platform_results',{}).get('codesys',{}).get('status','not_run')
    passed=r['compiles'] and r['tests_total']>0 and r['tests_passed']==r['tests_total']
    return dict(complete_code=evaluation.get('complete_code',False),compiles=r['compiles'],native_pass=native=='passed',
        native_eligible=native!='unsupported_platform',functional_pass=bool(passed),tests_passed=r['tests_passed'],tests_total=r['tests_total'],
        verification_status=evaluation['verification_status'],judge=r,feedback=evaluation['feedback'],timing=evaluation.get('timing',{}))

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
            if money(transport.upper(actual))>bound:
                transport.local_bound_error=True
                raise ProviderError('Frozen input bound exceeded before send')
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
        try:return original(*args)
        finally:
            path=transport.diagnostic_dir/'diagnostic.json'
            if path.exists():atomic_json(folder/(job['pid']+f'.transport_{idx+1:02}.json'),json.loads(sanitize(path.read_text(encoding='utf-8'))))
    transport.sender=sender;transport.before_send=before;transport.response_observer=observe
    return count

def generate_job(cfg,root,plan,job,budget,pending,*,factory=MeteredProvider,evaluator=evaluate,resume=False):
    folder=root/'jobs'/job['condition'];folder.mkdir(parents=True,exist_ok=True)
    if not resume:assert not list(folder.glob(job['pid']+'.*')),'Existing job evidence; no implicit replay'
    path=folder/(job['pid']+'.json');model=next(m for m in cfg['models'] if m['id']==job['model_id'])
    started=time.monotonic();deadline=started+2400;current=messages(job);fatal=None
    record=dict(job_id=job['job_id'],pid=job['pid'],condition=job['condition'],model=model['model'],
        experiment_kind='live',credential_batch='secondary',job_done=False,attempts=[],best_attempt=None,stop_reason='',tests_total=len(tasks()[job['pid']]['test_cases']),
        study_plan_sha256=sha(root/'study_plan.json'),started_at=stamp())
    prior_seconds=0;start_index=0
    if resume:
        record=load(path)
        assert record and not record['job_done'] and record['stop_reason'] in ('campaign_stopped_before_send','recovered_response_needs_repair')
        assert record['attempts'] and all(not a.get('provider_error') for a in record['attempts'])
        start_index=len(record['attempts']);assert start_index in (1,2,3)
        assert [a['idx'] for a in record['attempts']]==list(range(start_index))
        assert not (folder/(job['pid']+f'.request_{start_index+1:02}.json')).exists(),'Never repeat an existing request'
        strongest=record['attempts'][select_best(record['attempts'])]
        from policy import BOUNDARY_REVIEW
        progress=[dict(candidate=a['idx']+1,native_pass=a['native_pass'],functional_pass=a['functional_pass'],passed=a['tests_passed'],total=a['tests_total']) for a in record['attempts']]
        instruction=BOUNDARY_REVIEW+'\n'+strongest['feedback']+'\nPrevious candidate progress: '+json.dumps(progress,ensure_ascii=False)+'\nRepair the provided strongest candidate against public requirements and replay traces. Preserve previously correct behavior. Return complete code with the original interface and contract comments.'
        current=messages(job)+[dict(role='assistant',content=strongest['code']),dict(role='user',content=instruction)]
        prior_seconds=record['wall_seconds'];deadline=started+max(0,2400-prior_seconds)
        record.setdefault('resume_sessions',[]).append(dict(at=stamp(),next_candidate_index=start_index,previous_wall_seconds=prior_seconds))
        record.update(stop_reason='',error='')
    def save():
        record.update(best_attempt=select_best(record['attempts']),wall_seconds=round(prior_seconds+time.monotonic()-started,6),finished_at=stamp())
        atomic_json(path,record)
    try:
        with ExitStack() as stack:
            transport=factory(model,budget,max_tokens=16384,protocol=model['generation_protocol'],timeout=420)
            provider=transport
            if job['framework']=='codex':
                gateway=stack.enter_context(ResponsesGateway(provider=transport,model=transport.model))
                provider=InitialTextCodexProvider(gateway,model=transport.model,work_root=root/'cli_private',timeout=65 if transport.offline else 451)
            for idx in range(start_index,4):
                if deadline-time.monotonic()<451:record.update(job_done=True,stop_reason='insufficient_request_window');break
                capture(transport,budget,job,idx,pending,folder,root)
                call_started=time.monotonic()
                try:
                    queue_started=time.monotonic()
                    with API_SEMAPHORES[job['model_id']]:
                        if budget.coordinator.stopped.is_set():raise CampaignStopped('Stopped before generation')
                        call_started=time.monotonic();response=provider.generate(current)
                    generation_seconds=time.monotonic()-call_started
                    raw_source=extract_code(response.text);source,format_edits=normalize(raw_source)
                    (folder/(job['pid']+f'.raw_candidate_{idx+1:02}.st')).write_bytes(raw_source.encode())
                    digest=hashlib.sha256(source.encode()).hexdigest()
                    (folder/(job['pid']+f'.candidate_{idx+1:02}.st')).write_bytes(source.encode())
                    matched=next((a for a in record['attempts'] if a['code_hash']==digest),None)
                    if matched:
                        attempt=copy.deepcopy(matched);attempt.update(idx=idx,duplicate_of_candidate_index=matched['idx'])
                        record.update(job_done=True,stop_reason='repeated_candidate')
                    else:
                        result=evaluator(source,job['pid'],cfg,deadline);attempt=classify(result);attempt.update(idx=idx,code=source,code_hash=digest)
                        if result.get('shared_tool_error'):fatal=RuntimeError('Shared evaluation tool failure');record['stop_reason']='shared_tool_error'
                        elif not repairable(attempt):record.update(job_done=True,stop_reason='functional_pass_formal_'+attempt['verification_status'] if attempt['functional_pass'] else 'not_repairable')
                        elif idx==3:record.update(job_done=True,stop_reason='maximum_four_candidates')
                    attempt['engineering_contract']=compliance(source)
                    attempt.update(actual_model=response.model,prompt_tokens=response.usage['prompt_tokens'],completion_tokens=response.usage['completion_tokens'],
                        cost_cny=response.cost_cny,latency_s=round(generation_seconds,6),generation_seconds=round(generation_seconds,6),end_to_end_seconds=round(time.monotonic()-queue_started,6),format_edits=format_edits,raw_source_sha256=hashlib.sha256(raw_source.encode()).hexdigest(),provider_error='')
                    record['attempts'].append(attempt)
                    if fatal or record['job_done']:break
                    strongest=record['attempts'][select_best(record['attempts'])]
                    progress=[dict(candidate=a['idx']+1,native_pass=a['native_pass'],functional_pass=a['functional_pass'],passed=a['tests_passed'],total=a['tests_total']) for a in record['attempts']]
                    from policy import BOUNDARY_REVIEW
                    instruction=BOUNDARY_REVIEW+'\n'+strongest['feedback']+'\nPrevious candidate progress: '+json.dumps(progress,ensure_ascii=False)+'\nRepair the provided strongest candidate against public requirements and replay traces. Preserve previously correct behavior. Return complete code with the original interface and contract comments.'
                    current=messages(job)+[dict(role='assistant',content=strongest['code']),dict(role='user',content=instruction)]
                except CampaignStopped as exc:
                    record.update(job_done=False,stop_reason='campaign_stopped_before_send',error=str(exc));break
                except ProviderError as exc:
                    if getattr(transport,'local_bound_error',False):
                        # No upstream reservation or send occurred. Keep earlier valid candidates.
                        if idx==0:
                            record.update(job_done=False,stop_reason='initial_input_bound_changed_before_send')
                            fatal=exc;break
                        record.update(job_done=True,stop_reason='repair_input_limit_before_send',error='Complete repair context exceeds frozen input bound; no paid request sent')
                        break
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


# Scheduling, reporting and authorization are owned by f14_v10_study.py.

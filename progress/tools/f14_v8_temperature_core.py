"""Independent targeted repair; no hand-edited solution or oracle values in generation input."""
from contextlib import ExitStack
import copy
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
import f14_v6_core as parent
from f14_v8_temperature_budget import KIND,TOTAL,BASELINE,HISTORY,Coordinator,CampaignStopped,authorize
old=parent.old
REPO=parent.REPO
load,sha,stamp,atomic_json=parent.load,parent.sha,parent.stamp,parent.atomic_json
sanitize=parent.sanitize
money=parent.money
MeteredProvider=parent.MeteredProvider
ProviderError=parent.ProviderError
ResponsesGateway=parent.ResponsesGateway
InitialTextCodexProvider=parent.InitialTextCodexProvider
extract_code,normalize,compliance=parent.extract_code,parent.normalize,parent.compliance
credentials=parent.credentials
CONFIG=REPO/'progress/f14_v8_temperature_repair/config.json'
PACK=CONFIG.parent
RELEASE=REPO/'progress/f14_v7_boundary_review/release'
WORKER=REPO/'progress/f14_v7_boundary_review/judge_worker.py'
MIRROR=REPO/'progress/evidence/f14_v8_temperature_repair_20261113'
PID='public-medium-04'
API_SEMAPHORES={'deepseek-v4pro':threading.Semaphore(1)}
NATIVE_LOCK=threading.Lock()
FORMAL_SEMAPHORE=threading.Semaphore(1)


def config():
    cfg=load(CONFIG);original=parent.config()
    assert cfg['models']==[original['models'][0]] and cfg['limits']==original['limits']
    assert cfg['budget_cny']==TOTAL and cfg['study']['kind']==KIND
    assert cfg['study']['max_requests']==4 and cfg['study']['initial_spent_cny']==BASELINE and cfg['study']['initial_event_count']==HISTORY
    return cfg


def tasks():
    return {PID:load(RELEASE/'datasets/public'/ (PID+'.json'))}


def messages(job):
    assert job['pid']==PID
    return load(PACK/'initial_messages.json')['messages']


def files():
    paths=parent.files()+[p for p in PACK.glob('*') if p.is_file()]
    paths += [Path(__file__).with_name('f14_v8_temperature_'+name+'.py') for name in ('core','budget','study')]
    paths += [REPO/'progress/tests/test_f14_v8_temperature.py']
    paths += [WORKER,WORKER.parent/'v6_contracts.py',WORKER.parent/'contract_check.py']
    return sorted(set(paths))

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
            if money(transport.upper(actual))>bound:raise ProviderError('Frozen input bound exceeded before send')
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
    started=time.monotonic();deadline=started+2400;current=messages(job);fatal=None
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
            for idx in range(4):
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
                    instruction=strongest['feedback']+'\nPrevious candidate progress: '+json.dumps(progress,ensure_ascii=False)+'\nRepair the provided strongest candidate against public requirements and replay traces. Preserve previously correct behavior. Return complete code with the original interface and contract comments.'
                    current=messages(job)+[dict(role='assistant',content=strongest['code']),dict(role='user',content=instruction)]
                except CampaignStopped as exc:
                    record.update(job_done=False,stop_reason='campaign_stopped_before_send',error=str(exc));break
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


# Scheduling, reporting and authorization are owned by f14_v6_study.py.

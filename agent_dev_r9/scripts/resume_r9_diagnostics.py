"""Continue only unissued diagnostic jobs after one explicitly reviewed disconnect."""
import argparse
from contextlib import ExitStack
import ctypes
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys
import time
import uuid
import zipfile
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from stbench.campaign import configuration,digest,credential_check,tasks
from stbench.billing import canonical_ledger,ledger_lock
from stbench.evaluation import atomic_json
from stbench.platforms import CodesysBackend,OpenPLCBackend
from stbench.transport import MeteredProvider
from stbench.codex_baseline import ResponsesGateway,CodexProvider
from stbench.harness.engine import Solver,solve_problem
from stbench.harness.prompts import build_system_prompt
from stbench.providers.base import ProviderError
from campaign_status import load,registered_process_alive
from resume_user_paused_campaign import current_process_marker
from r9_diagnostics import scoped_budget,response_capture,status,summarize,CONCISE

ERROR='Upstream RemoteDisconnected; no automatic retry'


def state_hash(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,ensure_ascii=False).encode()).hexdigest()


def remaining_jobs(root,plan):
    pending=[]
    for job in plan['jobs']:
        path=Path(root)/'jobs'/(job['framework']+'_'+job['variant'])/(job['pid']+'.json')
        if not path.exists():
            if path.with_name(job['pid']+'.request.txt').exists() or path.with_name(job['pid']+'.response.json').exists():
                raise RuntimeError('An unrecorded request trace needs manual diagnosis before any reissue')
            pending.append(job)
        elif not load(path).get('attempts'):raise RuntimeError('An existing empty record needs manual diagnosis')
    return pending


def validate_disconnect(state,record,original_plan,resume):
    events=state.get('events',[]);event=events[-1] if events else {};details=state.get('halt_details',{})
    attempts=record.get('attempts',[]);last=attempts[0] if len(attempts)==1 else {}
    if (resume.get('action')!='user_continue_remaining_diagnostic_jobs' or
        state.get('halted')!='Unconfirmed upstream result; reservation retained' or
        state_hash(state)!=resume.get('ledger_state_sha256') or
        len(events)!=resume.get('event_count') or state.get('spent_cny')!=resume.get('spent_cny') or
        details.get('category')!='upstream_unconfirmed' or details.get('event_index')!=len(events)-1 or
        event.get('request_id')!=resume.get('request_id') or not event.get('request_id') or
        event.get('status')!='reserved' or event.get('phase')!='final' or
        event.get('phase_ceiling_cny')!=original_plan['cumulative_ceiling_cny'] or
        event.get('request')!={'model':'MiniMax-M2.7','protocol':'chat','timeout_seconds':420,'max_output_tokens':16384} or
        details.get('model')!='MiniMax-M2.7' or details.get('protocol')!='chat' or
        record.get('provider')!='openai-compat' or record.get('model')!='MiniMax-M2.7' or
        record.get('experiment_kind')!='live' or record.get('max_iters')!=1 or
        record.get('stop_reason')!='provider_error' or record.get('error')!=ERROR or
        len(attempts)!=1 or last.get('provider_error')!=ERROR or last.get('code') or last.get('actual_model') or
        last.get('prompt_tokens') or last.get('completion_tokens') or last.get('cost_cny') or
        not record.get('started_at',float('inf'))<=event.get('created_at',0)<=record.get('finished_at',0) or
        not 0<record.get('finished_at',0)-event.get('created_at',0)<420 or
        state.get('spent_cny',float('inf'))>=original_plan['cumulative_ceiling_cny'] or
        any(r.get('request_id')==event.get('request_id') for r in state.get('recoveries',[]))):
        raise RuntimeError('Only the unchanged, reviewed disconnect is eligible; no recovery applied')


def validate_checkpoint(cfg,resume,validation):
    root=Path(cfg['campaign_root']);plan=load(root/'diagnostic_plan.json')
    if resume.get('source_sha256')!=digest() or load(validation).get('source_sha256')!=digest() or load(validation).get('passed') is not True:
        raise RuntimeError('Current frozen source and offline validation are required')
    if plan.get('source_sha256')!=digest() or hashlib.sha256(json.dumps(cfg,sort_keys=True).encode()).hexdigest()!=plan['config_sha256']:
        raise RuntimeError('Diagnostic configuration changed')
    if hashlib.sha256((root/'diagnostic_plan.json').read_bytes()).hexdigest()!=resume['original_plan_sha256']:
        raise RuntimeError('Original diagnostic plan changed')
    if hashlib.sha256((ROOT/'scripts/r9_diagnostics.py').read_bytes()).hexdigest()!=plan['runner_sha256']:
        raise RuntimeError('The original diagnostic recipe changed')
    for name,expected in resume['job_file_hashes'].items():
        path=(root/name).resolve()
        if root.resolve() not in path.parents or hashlib.sha256(path.read_bytes()).hexdigest()!=expected:
            raise RuntimeError('Previously saved diagnostic evidence changed')
    with zipfile.ZipFile(root/'frozen_source_before_diagnostics.zip') as archive:
        for name in archive.namelist():
            if name.startswith(('stbench/','datasets/')) or name in ('scripts/r9_diagnostics.py','config.r9_diagnostic.json'):
                if hashlib.sha256(archive.read(name)).hexdigest()!=hashlib.sha256((ROOT/name).read_bytes()).hexdigest():
                    raise RuntimeError('Frozen generation or judgement source changed: '+name)
    pending=remaining_jobs(root,plan)
    if pending!=resume['remaining_jobs'] or len(pending)!=2:
        raise RuntimeError('The approved two unissued conditions changed')
    if sum((root/'jobs'/(j['framework']+'_'+j['variant'])/(j['pid']+'.json')).exists() for j in plan['jobs'])!=22:
        raise RuntimeError('Expected exactly 22 retained diagnostic records')
    native=load(root/'native_preflight.json')
    for backend in (CodesysBackend(cfg),OpenPLCBackend(cfg)):
        row=native.get(backend.name,{})
        if row.get('positive',{}).get('status')!='passed' or row.get('negative',{}).get('status')!='failed' or row['positive'].get('platform_identity')!=backend.identity():
            raise RuntimeError('Native control identity changed')
    failure=(root/resume['failure_relative_path']).resolve();failed_job=resume['failed_job']
    expected_failure=(root/'jobs'/(failed_job['framework']+'_'+failed_job['variant'])/(failed_job['pid']+'.json')).resolve()
    if failed_job not in plan['jobs'] or failed_job in pending or failure!=expected_failure:
        raise RuntimeError('The failed condition must be retained and excluded from continuation')
    record=load(failure)
    if record.get('pid')!=failed_job['pid']:raise RuntimeError('Failed task identity changed')
    if hashlib.sha256(failure.read_bytes()).hexdigest()!=resume['failure_sha256']:
        raise RuntimeError('Original disconnect record changed')
    ledger=canonical_ledger(cfg)
    with ledger_lock(ledger):
        state=scoped_budget(cfg,plan).read(allow_halted=True)
        validate_disconnect(state,record,plan,resume)
        if any(registered_process_alive(load(root/name)) for name in ('active_run.json','diagnostic_monitor.json')):
            raise RuntimeError('A diagnostic runner or monitor is still alive')
    return plan,record,pending


def release_disconnect(cfg,plan,resume,record,history,marker):
    root=Path(cfg['campaign_root']);ledger=canonical_ledger(cfg)
    with ledger_lock(ledger):
        state=scoped_budget(cfg,plan).read(allow_halted=True)
        validate_disconnect(state,record,plan,resume)
        if any(registered_process_alive(load(root/name)) for name in ('active_run.json','diagnostic_monitor.json')):
            raise RuntimeError('Duplicate diagnostic process refused')
        with (history/'ledger_before_resume.json').open('xb') as out:out.write(ledger.read_bytes())
        receipt=dict(reason='explicit_user_continue_only_unissued_diagnostic_jobs',request_id=resume['request_id'],
            spent_cny_unchanged=state['spent_cny'],event_count_unchanged=len(state['events']),
            unknown_reservations_retained=sum(e['reserved_cny'] for e in state['events'] if e['status']=='reserved'),
            current_unknown_retained=state['events'][-1]['reserved_cny'],cumulative_ceiling_cny=plan['cumulative_ceiling_cny'],
            backup=str(history/'ledger_before_resume.json'),created_at=time.time(),
            notice='No retry of the failed condition; all 22 saved records retained; future unknown results still halt')
        atomic_json(history/'resume_authorization.json',receipt)
        state.setdefault('recoveries',[]).append(receipt);state['halted']='';state.pop('halt_details',None)
        atomic_json(root/'active_run.json',marker)
        atomic_json(root/'diagnostic_state.json',dict(state='running',source_sha256=digest(),resume_id=marker['resume_id']))
        atomic_json(ledger,state)
    return receipt


def run_job(cfg,plan,job):
    root=Path(cfg['campaign_root']);folder=root/'jobs'/(job['framework']+'_'+job['variant'])
    path=folder/(job['pid']+'.json')
    if path.exists():raise RuntimeError('Refusing to replace or retry a saved condition')
    folder.mkdir(parents=True,exist_ok=True)
    p=next(p for _,p,_ in tasks() if p.pid==job['pid']);spec=cfg['models'][1];budget=scoped_budget(cfg,plan)
    with ExitStack() as stack:
        transport=MeteredProvider(spec,budget,max_tokens=16384,protocol='chat',timeout=420)
        transport.response_observer=response_capture(folder/(p.pid+'.response.json'))
        sent=[0]
        def one_request(messages):
            if sent[0]:raise ProviderError('Diagnostic single-request limit reached; no request sent')
            sent[0]+=1
            public=dict(model=spec['model'],protocol='chat',max_tokens=16384,timeout_seconds=420,
                        messages=[{k:m[k] for k in ('role','content') if k in m} for m in messages])
            text=re.sub(r'\bsk-[A-Za-z0-9_-]{16,}','[redacted]',json.dumps(public,ensure_ascii=False,indent=2))
            (folder/(p.pid+'.request.txt')).write_text(text,encoding='utf-8')
        transport.before_send=one_request
        if job['framework']=='codex':
            gateway=stack.enter_context(ResponsesGateway(provider=transport,model=spec['model']))
            provider=CodexProvider(gateway,model=spec['model'],work_root=Path(cfg['platform_root'])/'builds/codex_r9_diagnostics',timeout=450)
        else:provider=transport
        system=build_system_prompt()+('\n'+cfg['strategy'].get('extra_instruction','') if job['framework']=='custom' else '')
        if job['variant']=='concise':system+='\n'+CONCISE
        solver=Solver(provider,max_iters=1,system_prompt=system,include_ltl=True,model_check=True,
            verification_after_tests=True,task_seconds=1200,mc_seconds=30,request_window_seconds=450,
            backends=(CodesysBackend(cfg),),cache_dir=root/'cache'/(job['framework']+'_'+job['variant']))
        record=solve_problem(p,solver,log_dir=folder)
        print(job['pid'],job['framework'],job['variant'],record.solved,record.stop_reason,flush=True)
    budget.snapshot()


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--checkpoint',type=Path,required=True)
    ap.add_argument('--validation',type=Path,required=True);ap.add_argument('--check-only',action='store_true');args=ap.parse_args()
    cfg=configuration(str(ROOT/'config.r9_diagnostic.json'));root=Path(cfg['campaign_root']);resume=load(args.checkpoint)
    plan,record,pending=validate_checkpoint(cfg,resume,args.validation)
    if args.check_only:
        print(json.dumps(dict(passed=True,remaining=pending,incremental_cap=10,cumulative_ceiling=plan['cumulative_ceiling_cny'],generation_requests=0)),flush=True);return 0
    catalog=credential_check(cfg)
    if not all(catalog['selected_models'].values()):raise RuntimeError('Selected models absent from authenticated catalog')
    resume_id=uuid.uuid4().hex;history=root/'resume_history'/resume_id;history.mkdir(parents=True,exist_ok=False)
    for name in ('active_run.json','diagnostic_monitor.json','diagnostic_state.json','diagnostic_summary.json',
                 'r9_gate.json','response_structure_analysis.json','诊断结果.md','诊断状态.txt','诊断状态.html'):
        if (root/name).exists():shutil.copy2(root/name,history/name)
    atomic_json(history/'checkpoint.json',resume);atomic_json(history/'credential_check.json',catalog)
    with zipfile.ZipFile(history/'jobs_before_resume.zip','x',zipfile.ZIP_DEFLATED) as archive:
        for path in sorted((root/'jobs').rglob('*')):
            if path.is_file():archive.write(path,path.relative_to(root).as_posix())
    marker=dict(**current_process_marker(),state='running',source_sha256=digest(),entry='resume_r9_diagnostics.py',resume_id=resume_id,history=str(history))
    release_disconnect(cfg,plan,resume,record,history,marker)
    awake=False
    try:
        awake=bool(ctypes.windll.kernel32.SetThreadExecutionState(0x80000001))
        status(cfg)
        for job in pending:scoped_budget(cfg,plan).snapshot();run_job(cfg,plan,job);status(cfg)
        for name,expected in resume['job_file_hashes'].items():
            if hashlib.sha256((root/name).read_bytes()).hexdigest()!=expected:raise RuntimeError('Saved evidence changed while continuing')
        summarize(cfg,plan)
    except BaseException as error:
        atomic_json(root/'diagnostic_state.json',dict(state='stopped',error=str(error),source_sha256=digest(),resume_id=resume_id))
        marker['state']='stopped';raise
    else:
        atomic_json(root/'diagnostic_state.json',dict(state='completed',source_sha256=digest(),resume_id=resume_id,at=datetime.now(timezone.utc).isoformat()))
        marker['state']='completed'
    finally:
        if awake:ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
        atomic_json(root/'active_run.json',marker);status(cfg)
    return 0


if __name__=='__main__':raise SystemExit(main())

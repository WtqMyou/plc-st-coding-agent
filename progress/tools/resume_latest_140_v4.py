"""Inspected restart of V14. No resend, no historical refund, same frozen scoring policy."""
from concurrent.futures import ThreadPoolExecutor,wait,FIRST_COMPLETED
import copy
import ctypes
import hashlib
import inspect
import json
import os
from pathlib import Path
import sys
import threading
import subprocess
import time
import zipfile
import f14_v14_core as s
from f14_v14_budget import Coordinator
from f14_v14_study import publish
from f14_v14_status import report,record_for
from f14_v11_status import copy_changed
from stbench.billing import ledger_lock

LIMITS={'deepseek-v4pro':8,'minimax-m27':2}

class LongWaitCodex(s.InitialTextCodexProvider):
    def __init__(self,*args,**kwargs):
        if kwargs.get('model')=='MiniMax-M2.7' and kwargs.get('timeout')!=65:kwargs['timeout']=931
        super().__init__(*args,**kwargs)


def wait_ceiling(model_id):return 900 if model_id=='minimax-m27' else 420


def wrap_wait_transport(transport,job,root,started,prior_seconds,flags):
    original=transport.generate;ceiling=wait_ceiling(job['model_id']);transport.timeout=ceiling
    def generate(messages):
        remaining=2400-prior_seconds-(time.monotonic()-started)
        if remaining<ceiling+150:
            flags['task_window_stop']=True;transport.local_bound_error=True
            raise s.ProviderError('Insufficient task time for the reserved network wait and evaluation window')
        before=transport.before_send
        def with_wait_metadata(actual):
            before(actual)
            idx=transport.budget.context['candidate_index']
            path=root/'jobs'/job['condition']/(job['pid']+f'.request_{idx+1:02}.json')
            payload=s.load(path);payload.update(timeout_seconds=ceiling,operational_wait_policy='v4_wait900',task_seconds=2400)
            s.atomic_json(path,payload)
        transport.before_send=with_wait_metadata
        try:return original(messages)
        finally:transport.before_send=before
    transport.generate=generate
    return transport


def run_job_with_wait(generator,cfg,root,plan,job,budget,resume,*,factory=s.credentials.provider_factory,evaluator=s.evaluate):
    started=time.monotonic();path=root/'jobs'/job['condition']/(job['pid']+'.json')
    prior=s.load(path).get('wall_seconds',0) if resume else 0;flags={}
    def transport_factory(spec,view,**kwargs):
        kwargs['timeout']=wait_ceiling(job['model_id'])
        return wrap_wait_transport(factory(spec,view,**kwargs),job,root,started,prior,flags)
    record=generator(cfg,root,plan,job,budget,{},factory=transport_factory,evaluator=evaluator,resume=resume)
    record['operational_network_wait']=dict(batch='v4_wait900',ceiling_seconds=wait_ceiling(job['model_id']),task_seconds=2400,evaluation_reserve_seconds=150,model_parameters_unchanged=True)
    if flags.get('task_window_stop'):
        assert record['job_done'] and record['stop_reason']=='repair_input_limit_before_send'
        record.update(stop_reason='insufficient_request_window',error='Remaining task budget cannot fit another request and evaluation; no request sent')
    s.atomic_json(path,record)
    return record


def resume_attempt_allowed(attempt,record):
    return not attempt.get('provider_error') or (attempt['idx'] in record.get('manual_quota_rejected_indices',[]) and attempt.get('provider_error')=='Upstream HTTP 403' and not attempt.get('code'))

def retained_reply_kind(private):
    diag=s.load(private/'diagnostic.json');body=private/'http_body.bin'
    if diag.get('outcome')=='wall_deadline':
        assert diag['bytes_received']==0 and body.stat().st_size==0 and not (private/'worker_result.json').exists()
        return 'empty_timeout'
    assert diag.get('http_status')==403 and diag.get('outcome')=='http_error'
    raw=json.loads(body.read_bytes())
    assert raw.get('error',{}).get('code')=='insufficient_user_quota'
    assert not raw.get('usage') and not raw.get('output')
    return 'quota_rejected'

def resumed_generator():
    # The old, unused resume branch requested full ST. Normal V13/V14 repairs use exact JSON edits.
    # Only restore that same repair protocol on the first resumed request; fresh execution is untouched.
    source=inspect.getsource(s.generate_job)
    resume_start=source.index('    if resume:')
    start=source.index('        from v13_policy import BOUNDARY_REVIEW\n',source.index('    if resume:'))
    end=source.index('        prior_seconds=record[',start)
    patched=source[:start]+"        patch_base=strongest['code']\n        current=repair_messages(job,strongest,record['attempts'])\n"+source[end:]
    old_guard="assert record['attempts'] and all(not a.get('provider_error') for a in record['attempts'])"
    assert patched.count(old_guard)==1
    patched=patched.replace(old_guard,"assert record['attempts'] and all(resume_attempt_allowed(a,record) for a in record['attempts'])")
    namespace=dict(s.__dict__)
    namespace['resume_attempt_allowed']=resume_attempt_allowed
    namespace['InitialTextCodexProvider']=LongWaitCodex
    namespace['API_SEMAPHORES']={key:threading.Semaphore(value) for key,value in LIMITS.items()}
    exec(compile(patched,'<inspected-v14-resume>','exec'),namespace)
    return namespace['generate_job'],dict(original_sha256=hashlib.sha256(source.encode()).hexdigest(),
        resumed_sha256=hashlib.sha256(patched.encode()).hexdigest(),changed_branch='resume_context_and_explicit_manual_quota_rejection_guard',
        fresh_prefix_unchanged=patched[:resume_start]==source[:resume_start],execution_suffix_unchanged=patched[patched.index('        prior_seconds=record['):]==source[end:])

def paths(create=False):
    cfg=s.config();root=Path(cfg['campaign_root'])
    name='inspected_restart_wait900_'+s.stamp().replace(':','').replace('-','').split('.')[0] if create else s.load(root/'restart_v4_ready.json')['directory']
    return cfg,root,root/name

def show(cfg,plan,recovery):
    summary=report(cfg,plan);root=Path(cfg['campaign_root'])
    for p in recovery.glob('*'):
        if p.is_file() and 'ledger.' not in p.name and p.suffix in ('.json','.md','.log'):
            copy_changed(p,s.MIRROR/recovery.name/p.name)
    inspected=s.load(recovery/'recovery.json')
    notice=f"已人工复核并保留{len(inspected['unknown_requests'])}条历史异常请求的{inspected['retained_cost_cny']:.6f}元费用预留，旧记录不变。充值确认后从下一候选接续，拒绝记录仍计入每题最多4次请求。DeepSeek两组已完成。MiniMax两路接续，单次网络等待上限900秒，单题2400秒、最多4候选和输出24576保持；420/900秒批次分列记录。"
    summary['inspected_restart']=dict(retained_exception_count=len(inspected['unknown_requests']),retained_exception_cny=inspected['retained_cost_cny'],retained_timeout_count=sum(e.get('kind')=='empty_timeout' for e in inspected['unknown_requests']),request_limits=LIMITS,model_order='DeepSeek then MiniMax',recharge_confirmed_by_user=True)
    summary['network_wait_policy']=dict(current_minimax_wait_seconds=900,task_seconds=2400,historical_records_retained=True)
    cohorts={}
    for job in plan['jobs']+plan['imported_jobs']:
        seconds=900 if job['job_id'] in inspected['wait900_jobs'] else 420
        key=(job['condition'],seconds)
        row=cohorts.setdefault(key,dict(condition=job['condition'],network_wait_seconds=seconds,planned=0,completed=0,functional_passed=0,assertions_passed=0,assertions_total=0))
        row['planned']+=1;row['assertions_total']+=len(s.tasks()[job['pid']]['test_cases'])
        record=record_for(root,job)
        if record:
            row['completed']+=bool(record['job_done'])
            if record.get('best_attempt') is not None:
                best=record['attempts'][record['best_attempt']];row['functional_passed']+=bool(best['functional_pass']);row['assertions_passed']+=best['tests_passed']
    summary['wait_policy_cohorts']=list(cohorts.values())
    s.atomic_json(root/'wait_policy_breakdown.json',dict(rows=summary['wait_policy_cohorts'],task_seconds=2400,paired_minimax_task_sets_equal=True))
    copy_changed(root/'wait_policy_breakdown.json',s.MIRROR/'wait_policy_breakdown.json')
    s.atomic_json(root/'status.json',summary);copy_changed(root/'status.json',s.MIRROR/'status.json')
    for name in ('status.html','实验状态.md'):
        p=root/name;text=p.read_text(encoding='utf-8')
        text=text.replace('8题启动，完成4题后最多16题并行；每模型最多8请求','本次MiniMax最多2路，单次网络等待900秒，单题2400秒')
        if name.endswith('.html'):text=text.replace('</body>','')+'<p>'+notice+'</p>'
        else:
            text+='\n'+notice+'\n\n| 组别 | 网络等待/秒 | 完成/分母 | 功能通过 | 用例通过 |\n| --- | ---: | --- | ---: | --- |\n'
            for row in summary['wait_policy_cohorts']:
                text+=f"| {row['condition']} | {row['network_wait_seconds']} | {row['completed']}/{row['planned']} | {row['functional_passed']} | {row['assertions_passed']}/{row['assertions_total']} |\n"

        p.write_text(text,encoding='utf-8');copy_changed(p,s.MIRROR/name)
    if summary['state'].get('state')=='completed':copy_changed(root/'实验状态.md',s.MIRROR/'最终报告.md')
    return summary

def prepare():
    cfg,root,out=paths(True);plan=s.verify(cfg);path=Path(cfg['budget_ledger_path'])
    assert not s.old.old.support.registered_process_alive(s.load(root/'active_run.json'))
    assert not out.exists();out.mkdir()
    confirmation=s.load(root/'recharge_confirmation_20261113.json');assert confirmation['user_confirmed_recharge']
    before=path.read_bytes();state=json.loads(before);assert state['halted']=='Unconfirmed upstream result; reservation retained'
    assert s.sha(path)==s.load(root/'ledger_checkpoint.json')['sha256']
    assert state['limit_cny']==480 and s.money(state['spent_cny'])<s.money(480)
    (out/'ledger.before.json').write_bytes(before)
    completed={};continued={};unknown=[];records={}
    events=state['events'][s.HISTORY:]
    for job in plan['jobs']:
        p=root/'jobs'/job['condition']/(job['pid']+'.json');record=s.load(p)
        if not record:continue
        (out/'records.before'/job['condition']).mkdir(parents=True,exist_ok=True)
        (out/'records.before'/job['condition']/p.name).write_bytes(p.read_bytes())
        records[job['job_id']]=s.sha(p)
        if record['job_done']:completed[job['job_id']]=s.sha(p)
    for event in events:
        if event['status']=='settled':continue
        req=event['request'];condition,pid=req['job_id'].split('/');idx=req['candidate_index']
        private=root/'transport_private'/condition/pid/str(idx);diag=s.load(private/'diagnostic.json')
        kind=retained_reply_kind(private)
        p=root/'jobs'/condition/(pid+'.json');record=s.load(p);a=record['attempts'][idx]
        assert a['provider_error'] and not a['code']
        if kind=='quota_rejected':
            assert a['provider_error']=='Upstream HTTP 403'
            if not record['job_done']:
                a['unknown_cost_reservation_cny']=event['reserved_cny']
                a['rejected_for_account_quota']=True
                record['manual_quota_rejected_indices']=sorted(set(record.get('manual_quota_rejected_indices',[])+[idx]))
                record.update(stop_reason='recovered_response_needs_repair',best_attempt=s.select_best(record['attempts']))
                s.atomic_json(p,record)
            else:assert s.money(a['unknown_cost_reservation_cny'])==s.money(event['reserved_cny'])
        elif not record['job_done']:
            assert record['stop_reason']=='provider_error'
            a['unknown_cost_reservation_cny']=event['reserved_cny']
            record.update(job_done=True,stop_reason='inspected_timeout_no_retry_reservation_retained',best_attempt=s.select_best(record['attempts']))
            s.atomic_json(p,record)
        else:
            assert record['stop_reason']=='inspected_timeout_no_retry_reservation_retained'
            assert s.money(a['unknown_cost_reservation_cny'])==s.money(event['reserved_cny'])
        unknown.append(dict(request_id=event['request_id'],job_id=req['job_id'],candidate_index=idx,reserved_cny=event['reserved_cny'],kind=kind))
    assert unknown
    retained=sum((s.money(e['reserved_cny']) for e in unknown),s.money(0))
    for job in plan['jobs']:
        p=root/'jobs'/job['condition']/(job['pid']+'.json');record=s.load(p)
        if record and not record['job_done']:
            assert record['stop_reason'] in ('campaign_stopped_before_send','recovered_response_needs_repair') and all(resume_attempt_allowed(a,record) for a in record['attempts'])
            idx=len(record['attempts']);assert idx in (1,2,3) and s.select_for_repair(record['attempts']) is not None
            assert not (p.parent/(job['pid']+f'.request_{idx+1:02}.json')).exists()
            assert not any(e['request']['job_id']==job['job_id'] and e['request']['candidate_index']==idx for e in events)
            continued[job['job_id']]=s.sha(p)
    _,proof=resumed_generator();assert proof['fresh_prefix_unchanged'] and proof['execution_suffix_unchanged']
    co=Coordinator(path,dict(plan,sha256=s.sha(root/'study_plan.json'),ledger_before=str(root/'ledger_before_study.json')))
    for job in plan['jobs']:
        if s.load(root/'jobs'/job['condition']/(job['pid']+'.json')).get('job_done'):co.finish(job['job_id'])
    pending=sum((v for values in co.pending.values() for v in values.values()),s.money(0))
    assert s.money(state['spent_cny'])+pending<=s.money(480)
    tests=Path('E:/PLC_Dev/evidence/restart_latest_140_v4_tests_20261113.log').read_bytes();assert tests.rstrip().endswith(b'OK')
    (out/'tests.log').write_bytes(tests)
    wait_jobs=[j['job_id'] for j in plan['jobs'] if j['job_id'] in co.pending]
    wait_sets={c:{j['pid'] for j in plan['jobs'] if j['job_id'] in wait_jobs and j['condition']==c} for c in ('custom_minimax-m27','codex_minimax-m27')}
    assert wait_sets['custom_minimax-m27']==wait_sets['codex_minimax-m27'] and len(wait_jobs)==52
    descriptor=dict(passed=True,user_instruction='怎么又停了？？重启',recharge_confirmation_sha256=s.sha(root/'recharge_confirmation_20261113.json'),original_plan_sha256=s.sha(root/'study_plan.json'),
        wait900_jobs=wait_jobs,unknown_requests=unknown,completed_before_hashes=completed,continued_record_hashes=continued,records_before_hashes=records,
        retained_cost_cny=float(retained),accounted_cny=state['spent_cny'],events_before=len(state['events']),
        remaining_jobs=len(co.pending),request_limits=LIMITS,maximum_parallel_jobs=10,network_wait_seconds={'deepseek-v4pro':420,'minimax-m27':900},task_seconds=2400,evaluation_reserve_seconds=150,prior_wait_records_preserved=True,
        remaining_reserved_cny=float(pending),worst_cumulative_cny=float(s.money(state['spent_cny'])+pending),resume_context=proof,
        files={str(p.relative_to(s.REPO)).replace('\\','/'):s.sha(p) for p in (Path(__file__).resolve(),s.REPO/'progress/tests/test_resume_latest_140_v4.py')},at=s.stamp())
    s.atomic_json(out/'recovery.json',descriptor)
    with ledger_lock(path):
        assert path.read_bytes()==before
        after=copy.deepcopy(state);after['historical_halts'].append(dict(reason=state['halted'],details=state.get('halt_details'),retained=True,at=s.stamp()))
        after['halted']='';after.pop('halt_details',None);after.setdefault('recoveries',[]).append(dict(kind=s.KIND,reason='explicit_recharge_and_manual_resume_after_quota_rejection',
            user_instruction=descriptor['user_instruction'],recovery_sha256=s.sha(out/'recovery.json'),unknown_requests_retained=unknown,requests_resent=0,at=s.stamp()))
        after['f14_v14_authorization'].setdefault('inspected_restarts',[]).append(dict(recovery_sha256=s.sha(out/'recovery.json'),request_limits=LIMITS))
        assert after['events']==state['events'] and after['spent_cny']==state['spent_cny']
        s.atomic_json(path,after)
    s.atomic_json(out/'ready.json',dict(recovery_sha256=s.sha(out/'recovery.json'),ledger_sha256=s.sha(path)))
    s.atomic_json(root/'restart_v4_ready.json',dict(directory=out.name,recovery_sha256=s.sha(out/'recovery.json')))
    s.atomic_json(root/'study_state.json',dict(state='resume_ready',new_completed=120-len(co.pending),at=s.stamp()))
    show(cfg,plan,out);print('READY',len(unknown),'retained timeouts;',len(co.pending),'pending; worst cumulative',descriptor['worst_cumulative_cny'],flush=True)

def audit(cfg,plan,descriptor):
    root=Path(cfg['campaign_root']);state=s.load(cfg['budget_ledger_path']);assert s.prefix_ok(state,s.load(root/'ledger_before_study.json'))
    events=state['events'][s.HISTORY:];linked={(e['request']['job_id'],e['request']['candidate_index']):e for e in events}
    assert len(events)==len(linked)<=480
    retained={e['request_id'] for e in descriptor['unknown_requests']};calls=0;passed=0;cases=0
    for job in plan['jobs']+plan['imported_jobs']:
        record=record_for(root,job);assert record['job_done'] and 1<=len(record['attempts'])<=4
        folder=Path(job['source_record']).parent if job.get('imported') else root/'jobs'/job['condition']
        for a in record['attempts']:
            if not job.get('imported'):
                event=linked[(job['job_id'],a['idx'])];calls+=1
                if event['request_id'] in retained:
                    assert event['status']=='reserved' and a.get('provider_error') and not a['code']
                    assert s.money(a['unknown_cost_reservation_cny'])==s.money(event['reserved_cny'])
                else:
                    assert event['status']=='settled' and s.money(event['accounted_cny'])==s.money(a['cost_cny'])
                    assert event['metadata']['model']==a['actual_model']
            if a.get('code'):
                assert s.sha(folder/(job['pid']+f'.candidate_{a["idx"]+1:02}.st'))==a['code_hash']
                if a.get('model_patch',{}).get('mode') in ('model_exact_edits','model_replacement'):
                    from v13_repairs import apply
                    base=(folder/(job['pid']+f'.patch_base_{a["idx"]+1:02}.st')).read_bytes().decode('utf-8')
                    patch=s.load(folder/(job['pid']+f'.model_patch_{a["idx"]+1:02}.json'));expanded,_=apply(patch['raw_model_text'],base)
                    assert s.normalize(expanded)[0]==a['code']
        best=record['attempts'][record['best_attempt']];passed+=best['functional_pass'];cases+=best['tests_passed']
    assert calls==len(events) and {e['request_id'] for e in events if e['status']=='reserved'}==retained
    for key,digest in descriptor['completed_before_hashes'].items():assert s.sha(root/'jobs'/(key+'.json'))==digest
    result=dict(passed=True,combined_jobs=140,new_jobs=120,imported_jobs=20,new_requests=calls,functional_passed=passed,
        assertions_passed=cases,assertions_total=3784,unknown_requests_retained=len(retained),unknown_reserved_cny=descriptor['retained_cost_cny'],
        original_completed_records_preserved=True,accounted_cny=state['spent_cny'],at=s.stamp())
    s.atomic_json(root/'final_audit.json',result);return result

def next_job_index(pending,active):
    counts={key:sum(j['model_id']==key for j in active.values()) for key in LIMITS}
    deepseek_left=any(j['model_id']=='deepseek-v4pro' for j in pending) or counts['deepseek-v4pro']>0
    model='deepseek-v4pro' if deepseek_left else 'minimax-m27'
    return next((i for i,j in enumerate(pending) if j['model_id']==model and counts[model]<LIMITS[model]),None)

def live():
    cfg,root,out=paths();plan=s.verify(cfg);descriptor=s.load(out/'recovery.json');ready=s.load(out/'ready.json')
    assert descriptor['recharge_confirmation_sha256']==s.sha(root/'recharge_confirmation_20261113.json')
    assert ready['recovery_sha256']==s.sha(out/'recovery.json') and ready['ledger_sha256']==s.sha(cfg['budget_ledger_path'])
    for rel,digest in descriptor['files'].items():assert s.sha(s.REPO/rel)==digest
    assert s.load(root/'study_state.json')['state']=='resume_ready'
    s.old.old.support.no_other_runner(cfg)
    for attempt in range(3):
        try:s.old.ensure_pushed();break
        except (subprocess.CalledProcessError,subprocess.TimeoutExpired):
            if attempt==2:raise
            time.sleep(1)
    binding=s.credentials.load_credentials(cfg);catalog=s.credentials.catalog(cfg,'secondary')
    assert binding['secondary']==s.load(root/'run_environment.json')['secondary_key_sha256']
    s.atomic_json(out/'environment.json',dict(catalog=catalog,at=s.stamp(),model_parameters_changed=False,recharge_confirmed_by_user=True,operational_network_wait_seconds=900))
    s.atomic_json(root/'wait900_resume_20261113.json',dict(network_wait_seconds=900,at=s.stamp(),old_quota_block_preserved=True))
    generator,proof=resumed_generator();assert proof==descriptor['resume_context']
    budget=Coordinator(cfg['budget_ledger_path'],dict(plan,sha256=s.sha(root/'study_plan.json'),ledger_before=str(root/'ledger_before_study.json')))
    pending=[];done=0
    for job in plan['jobs']:
        record=s.load(root/'jobs'/job['condition']/(job['pid']+'.json'))
        if record.get('job_done'):budget.finish(job['job_id']);done+=1
        else:
            if record:assert descriptor['continued_record_hashes'][job['job_id']]==s.sha(root/'jobs'/job['condition']/(job['pid']+'.json'))
            pending.append(job)
    active={};error=None;published=done
    s.atomic_json(root/'active_run.json',dict(**s.old.old.support.current_process_marker(),state='running',entry='resume_latest_140_v4.py'))
    try:
        if os.name=='nt':ctypes.windll.kernel32.SetThreadExecutionState(0x80000001)
        with ThreadPoolExecutor(max_workers=10,thread_name_prefix='inspected-resume') as pool:
            while pending or active:
                while len(active)<10 and not budget.stopped.is_set():
                    idx=next_job_index(pending,active)
                    if idx is None:break
                    s.verify(cfg);job=pending.pop(idx);path=root/'jobs'/job['condition']/(job['pid']+'.json')
                    active[pool.submit(run_job_with_wait,generator,cfg,root,plan,job,budget.view(job['job_id']),path.exists())]=job
                s.atomic_json(root/'study_state.json',dict(state='running',new_completed=done,imported_completed=20,
                    active_jobs=[j['job_id'] for j in active.values()],workers=10,per_model_limits=LIMITS,at=s.stamp()))
                show(cfg,plan,out)
                if not active:break
                completed,_=wait(active,timeout=10,return_when=FIRST_COMPLETED)
                for future in completed:
                    job=active.pop(future)
                    try:
                        record=future.result();assert record['job_done'];budget.finish(job['job_id']);done+=1
                        print('FINISHED',job['job_id'],done,'/120',flush=True)
                    except BaseException as exc:error=s.sanitize(type(exc).__name__+': '+str(exc));budget.halt(error)
                if done-published>=4:show(cfg,plan,out);publish();published=done
        assert done==120 and not budget.stopped.is_set(),error or 'Stopped with evidence retained'
        result=audit(cfg,plan,descriptor);s.atomic_json(root/'completion.json',dict(**result,completed=True))
        s.atomic_json(root/'study_state.json',dict(state='completed',combined_completed=140,new_completed=120,at=s.stamp()))
        budget.halt('LATEST_140_COMPLETE_WITH_RETAINED_TIMEOUTS')
    except BaseException as exc:
        s.atomic_json(root/'study_state.json',dict(state='stopped',new_completed=done,error=s.sanitize(str(exc)),at=s.stamp()));raise
    finally:
        if os.name=='nt':ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
        s.atomic_json(root/'active_run.json',dict(state='ended',at=s.stamp()));s.atomic_json(root/'ledger_checkpoint.json',dict(sha256=s.sha(cfg['budget_ledger_path']),at=s.stamp()))
        show(cfg,plan,out)
        if s.load(root/'study_state.json')['state']=='completed':
            with zipfile.ZipFile(s.MIRROR/'验收包.zip','w',zipfile.ZIP_DEFLATED) as z:
                for p in s.MIRROR.rglob('*'):
                    if p.is_file() and p.suffix!='.zip':z.write(p,p.relative_to(s.MIRROR))
        publish()

if __name__=='__main__':
    {'prepare':prepare,'live':live}[sys.argv[1]]()

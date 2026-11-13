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
import zipfile
import f14_v14_core as s
from f14_v14_budget import Coordinator
from f14_v14_study import publish
from f14_v14_status import report,record_for
from f14_v11_status import copy_changed
from stbench.billing import ledger_lock

LIMITS={'deepseek-v4pro':8,'minimax-m27':4}

def resumed_generator():
    # The old, unused resume branch requested full ST. Normal V13/V14 repairs use exact JSON edits.
    # Only restore that same repair protocol on the first resumed request; fresh execution is untouched.
    source=inspect.getsource(s.generate_job)
    start=source.index('        from v13_policy import BOUNDARY_REVIEW\n',source.index('    if resume:'))
    end=source.index('        prior_seconds=record[',start)
    patched=source[:start]+"        patch_base=strongest['code']\n        current=repair_messages(job,strongest,record['attempts'])\n"+source[end:]
    namespace=dict(s.__dict__)
    namespace['API_SEMAPHORES']={key:threading.Semaphore(value) for key,value in LIMITS.items()}
    exec(compile(patched,'<inspected-v14-resume>','exec'),namespace)
    return namespace['generate_job'],dict(original_sha256=hashlib.sha256(source.encode()).hexdigest(),
        resumed_sha256=hashlib.sha256(patched.encode()).hexdigest(),changed_branch='resume_context_only',
        fresh_prefix_unchanged=patched[:start]==source[:start],execution_suffix_unchanged=patched[patched.index('        prior_seconds=record['):]==source[end:])

def paths():
    cfg=s.config();root=Path(cfg['campaign_root']);return cfg,root,root/'inspected_restart_20261113'

def show(cfg,plan,recovery):
    summary=report(cfg,plan);root=Path(cfg['campaign_root'])
    for p in recovery.glob('*'):
        if p.is_file() and 'ledger.' not in p.name and p.suffix in ('.json','.md','.log'):
            copy_changed(p,s.MIRROR/recovery.name/p.name)
    notice='本次人工检查后保留3条无返回请求的0.600414元费用预留；未重发这些请求。MiniMax并发4、DeepSeek并发8；每题候选数和时间上限保持。'
    summary['inspected_restart']=dict(retained_timeout_count=3,retained_timeout_cny=.600414,request_limits=LIMITS)
    s.atomic_json(root/'status.json',summary);copy_changed(root/'status.json',s.MIRROR/'status.json')
    for name in ('status.html','实验状态.md'):
        p=root/name;text=p.read_text(encoding='utf-8')
        text=text.replace('最多16题并行','最多12题并行').replace('每模型最多8请求','DeepSeek最多8请求、MiniMax最多4请求')
        if name.endswith('.html'):text=text.replace('</body>','')+'<p>'+notice+'</p>'
        else:text+='\n'+notice+'\n'
        p.write_text(text,encoding='utf-8');copy_changed(p,s.MIRROR/name)
    return summary

def prepare():
    cfg,root,out=paths();plan=s.verify(cfg);path=Path(cfg['budget_ledger_path'])
    assert not s.old.old.support.registered_process_alive(s.load(root/'active_run.json'))
    assert not out.exists();out.mkdir()
    before=path.read_bytes();state=json.loads(before);assert state['halted']=='Unconfirmed upstream result; reservation retained'
    assert s.sha(path)==s.load(root/'ledger_checkpoint.json')['sha256']
    assert state['limit_cny']==480 and (state['spent_cny'],len(state['events']))==(187.318389,1747)
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
        assert diag['outcome']=='wall_deadline' and diag['bytes_received']==0
        assert (private/'http_body.bin').stat().st_size==0 and not (private/'worker_result.json').exists()
        p=root/'jobs'/condition/(pid+'.json');record=s.load(p);a=record['attempts'][idx]
        assert a['provider_error'] and not a['code'] and record['stop_reason']=='provider_error'
        a['unknown_cost_reservation_cny']=event['reserved_cny']
        record.update(job_done=True,stop_reason='inspected_timeout_no_retry_reservation_retained',best_attempt=s.select_best(record['attempts']))
        s.atomic_json(p,record)
        unknown.append(dict(request_id=event['request_id'],job_id=req['job_id'],candidate_index=idx,reserved_cny=event['reserved_cny']))
    assert len(unknown)==3 and sum((s.money(e['reserved_cny']) for e in unknown),s.money(0))==s.money(.600414)
    for job in plan['jobs']:
        p=root/'jobs'/job['condition']/(job['pid']+'.json');record=s.load(p)
        if record and not record['job_done']:
            assert record['stop_reason']=='campaign_stopped_before_send' and all(not a.get('provider_error') for a in record['attempts'])
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
    tests=Path('E:/PLC_Dev/evidence/restart_latest_140_tests_20261113.log').read_bytes();assert tests.rstrip().endswith(b'OK')
    (out/'tests.log').write_bytes(tests)
    descriptor=dict(passed=True,user_instruction='实验停止，检查并重启',original_plan_sha256=s.sha(root/'study_plan.json'),
        unknown_requests=unknown,completed_before_hashes=completed,continued_record_hashes=continued,records_before_hashes=records,
        retained_cost_cny=.600414,accounted_cny=state['spent_cny'],events_before=len(state['events']),
        remaining_jobs=len(co.pending),request_limits=LIMITS,maximum_parallel_jobs=12,
        remaining_reserved_cny=float(pending),worst_cumulative_cny=float(s.money(state['spent_cny'])+pending),resume_context=proof,
        files={str(p.relative_to(s.REPO)).replace('\\','/'):s.sha(p) for p in (Path(__file__).resolve(),s.REPO/'progress/tests/test_resume_latest_140.py')},at=s.stamp())
    s.atomic_json(out/'recovery.json',descriptor)
    with ledger_lock(path):
        assert path.read_bytes()==before
        after=copy.deepcopy(state);after['historical_halts'].append(dict(reason=state['halted'],details=state.get('halt_details'),retained=True,at=s.stamp()))
        after['halted']='';after.setdefault('recoveries',[]).append(dict(kind=s.KIND,reason='manual_inspection_of_three_empty_timeout_responses',
            user_instruction=descriptor['user_instruction'],recovery_sha256=s.sha(out/'recovery.json'),unknown_requests_retained=unknown,requests_resent=0,at=s.stamp()))
        after['f14_v14_authorization'].setdefault('inspected_restarts',[]).append(dict(recovery_sha256=s.sha(out/'recovery.json'),request_limits=LIMITS))
        assert after['events']==state['events'] and after['spent_cny']==state['spent_cny']
        s.atomic_json(path,after)
    s.atomic_json(out/'ready.json',dict(recovery_sha256=s.sha(out/'recovery.json'),ledger_sha256=s.sha(path)))
    s.atomic_json(root/'study_state.json',dict(state='resume_ready',new_completed=14,at=s.stamp()))
    show(cfg,plan,out);print('READY 3 timeouts retained, 12 partial jobs +94 fresh; worst cumulative',descriptor['worst_cumulative_cny'],flush=True)

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
        assertions_passed=cases,assertions_total=3784,unknown_requests_retained=3,unknown_reserved_cny=.600414,
        original_completed_records_preserved=True,accounted_cny=state['spent_cny'],at=s.stamp())
    s.atomic_json(root/'final_audit.json',result);return result

def live():
    cfg,root,out=paths();plan=s.verify(cfg);descriptor=s.load(out/'recovery.json');ready=s.load(out/'ready.json')
    assert ready['recovery_sha256']==s.sha(out/'recovery.json') and ready['ledger_sha256']==s.sha(cfg['budget_ledger_path'])
    for rel,digest in descriptor['files'].items():assert s.sha(s.REPO/rel)==digest
    assert s.load(root/'study_state.json')['state']=='resume_ready'
    s.old.old.support.no_other_runner(cfg);s.old.ensure_pushed()
    binding=s.credentials.load_credentials(cfg);catalog=s.credentials.catalog(cfg,'secondary')
    assert binding['secondary']==s.load(root/'run_environment.json')['secondary_key_sha256']
    s.atomic_json(out/'environment.json',dict(catalog=catalog,at=s.stamp(),model_parameters_changed=False))
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
    s.atomic_json(root/'active_run.json',dict(**s.old.old.support.current_process_marker(),state='running',entry='resume_latest_140.py'))
    try:
        if os.name=='nt':ctypes.windll.kernel32.SetThreadExecutionState(0x80000001)
        with ThreadPoolExecutor(max_workers=12,thread_name_prefix='inspected-resume') as pool:
            while pending or active:
                while len(active)<12 and not budget.stopped.is_set():
                    counts={key:sum(j['model_id']==key for j in active.values()) for key in LIMITS}
                    idx=next((i for i,j in enumerate(pending) if counts[j['model_id']]<LIMITS[j['model_id']]),None)
                    if idx is None:break
                    s.verify(cfg);job=pending.pop(idx);path=root/'jobs'/job['condition']/(job['pid']+'.json')
                    active[pool.submit(generator,cfg,root,plan,job,budget.view(job['job_id']),{},factory=s.credentials.provider_factory,resume=path.exists())]=job
                s.atomic_json(root/'study_state.json',dict(state='running',new_completed=done,imported_completed=20,
                    active_jobs=[j['job_id'] for j in active.values()],workers=12,per_model_limits=LIMITS,at=s.stamp()))
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
        budget.halt('LATEST_140_COMPLETE_WITH_THREE_RETAINED_TIMEOUTS')
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

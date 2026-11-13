"""Inspected V10 recovery: replay captured replies locally, never resend an HTTP request."""
import copy
import hashlib
import json
from pathlib import Path
import shutil
import time
import f14_v10_core as s
from stbench.transport import validate_response
from stbench.billing import ledger_lock

def main():
    cfg=s.config();root=Path(cfg['campaign_root']);out=root/'recovery_io_resume_20261113'
    assert out.is_dir() and not (out/'recovery.json').exists()
    ledger_path=Path(cfg['budget_ledger_path']);before=s.load(out/'ledger.before.json')
    assert ledger_path.read_bytes()==(out/'ledger.before.json').read_bytes(),'Another process changed the ledger'
    snapshot=s.load(out/'study_plan.json.before');plan=s.load(root/'study_plan.json')
    assert {k:v for k,v in plan.items() if k!='files'}=={k:v for k,v in snapshot.items() if k!='files'}
    assert s.load(out/'test_outcome.json')['passed']
    fixed=[]
    for condition,pid in [('codex_deepseek-v4pro','public-easy-03'),('codex_deepseek-v4pro','self-medium-06')]:
        event=next(e for e in before['events'][s.HISTORY:] if e['request']['job_id']==condition+'/'+pid and e['status']=='reserved')
        idx=event['request']['candidate_index'];private=root/'transport_private'/condition/pid/str(idx)
        raw=s.load(private/'worker_result.json');assert raw['ok']
        response=raw['data'];model=next(m for m in cfg['models'] if m['id']=='deepseek-v4pro')
        v=validate_response(response,'responses',model['accepted_models']);assert v['complete']
        cost=s.money((v['prompt_tokens']*model['input_cny_per_million']+v['completion_tokens']*model['output_cny_per_million'])/1e6)
        assert cost<=s.money(event['reserved_cny'])
        folder=root/'jobs'/condition;path=folder/(pid+'.json');record=s.load(path)
        if not record['job_done'] and not record['attempts'][idx].get('recovered_from_completed_http_response'):
            s.atomic_json(folder/(pid+f'.response_{idx+1:02}.json'),dict(protocol='responses',raw_response=response))
            raw_code=s.extract_code(v['text']);source,edits=s.normalize(raw_code)
            evaluated=s.evaluate(source,pid,cfg,time.monotonic()+600);assert not evaluated.get('shared_tool_error')
            a=s.classify(evaluated);a.update(idx=idx,code=source,code_hash=hashlib.sha256(source.encode()).hexdigest(),
                engineering_contract=s.compliance(source),actual_model=v['model'],prompt_tokens=v['prompt_tokens'],completion_tokens=v['completion_tokens'],
                cost_cny=float(cost),latency_s=record['attempts'][idx].get('latency_s'),format_edits=edits,raw_source_sha256=hashlib.sha256(raw_code.encode()).hexdigest(),provider_error='',
                recovered_from_completed_http_response=True)
            (folder/(pid+f'.raw_candidate_{idx+1:02}.st')).write_bytes(raw_code.encode())
            (folder/(pid+f'.candidate_{idx+1:02}.st')).write_bytes(source.encode())
            record['attempts'][idx]=a;record['best_attempt']=s.select_best(record['attempts'])
            record.update(job_done=not s.repairable(a),stop_reason='recovered_response_complete' if not s.repairable(a) else 'recovered_response_needs_repair',error='')
            s.atomic_json(path,record)
        else:
            a=record['attempts'][idx]
            assert s.money(a['cost_cny'])==cost and a['actual_model']==v['model']
        fixed.append(dict(request_id=event['request_id'],job_id=condition+'/'+pid,candidate_index=idx,cost_cny=float(cost),
            metadata=dict(model=v['model'],prompt_tokens=v['prompt_tokens'],completion_tokens=v['completion_tokens'],finish_reason=v['finish_reason'],protocol='responses',recovery='validated_original_http_capture')))
    # An empty timed-out HTTP body cannot be reconstructed and is never sent again.
    unknown=[e for e in before['events'][s.HISTORY:] if e['status']=='reserved' and e['request_id'] not in {f['request_id'] for f in fixed}]
    assert len(unknown)==1
    event=unknown[0];condition,pid=event['request']['job_id'].split('/');idx=event['request']['candidate_index']
    private=root/'transport_private'/condition/pid/str(idx);diag=s.load(private/'diagnostic.json')
    assert diag['outcome']=='wall_deadline' and diag['bytes_received']==0 and (private/'http_body.bin').stat().st_size==0
    path=root/'jobs'/condition/(pid+'.json');record=s.load(path)
    assert record['attempts'][idx]['provider_error'] and not record['attempts'][idx].get('code')
    record.update(job_done=True,stop_reason='confirmed_timeout_no_retry_reservation_retained',error='',best_attempt=s.select_best(record['attempts']))
    record['attempts'][idx]['unknown_cost_reservation_cny']=event['reserved_cny'];s.atomic_json(path,record)
    retained=dict(request_ids=[event['request_id']],amount_cny=event['reserved_cny'],no_response=True,no_retry=True,
        user_instruction='修复好后赶紧重启实验',resolution='Unknown charge remains fully reserved; prior failed invocation is not repeated')
    s.atomic_json(root/'timeout_reservations.json',retained)
    for job,digest in s.load(out/'completed_hashes.json').items():
        condition,pid=job.split('/');assert s.sha(root/'jobs'/condition/(pid+'.json'))==digest,'Completed job changed'
    validation=s.load(root/'validation.json');validation['operational_io_resume_tests']=(out/'tests.log').read_text(encoding='utf-8')
    s.atomic_json(root/'validation.json',validation)
    plan['files']={p.relative_to(s.REPO).as_posix():s.sha(p) for p in s.files()}
    s.atomic_json(root/'study_plan.json',plan);new_sha=s.sha(root/'study_plan.json')
    with ledger_lock(ledger_path):
        assert ledger_path.read_bytes()==(out/'ledger.before.json').read_bytes()
        after=copy.deepcopy(before)
        for fix in fixed:
            e=next(e for e in after['events'] if e.get('request_id')==fix['request_id']);assert e['status']=='reserved'
            after['spent_cny']=float(s.money(after['spent_cny'])-s.money(e['reserved_cny'])+s.money(fix['cost_cny']))
            e.update(status='settled',accounted_cny=fix['cost_cny'],metadata=fix['metadata'])
        assert after['events'][:s.HISTORY]==before['events'][:s.HISTORY]
        assert len(after['events'])==len(before['events'])
        after['halted']=''
        auth=after['f14_v10_authorization'];auth.setdefault('operational_plan_sha256',[]).append(new_sha)
        after['recoveries'].append(dict(kind=s.KIND,reason='transient_windows_file_sharing_and_inspected_timeout_resume',
            old_plan_sha256=s.sha(out/'study_plan.json.before'),new_plan_sha256=new_sha,settled_captured_responses=fixed,
            retained_timeout=retained,external_model_calls=0,user_instruction='修复好后赶紧重启实验',at=s.stamp()))
        assert s.money(after['spent_cny'])<=s.money(420);s.atomic_json(ledger_path,after)
    s.atomic_json(root/'prepared.json',dict(plan_sha256=new_sha,validation_sha256=s.sha(root/'validation.json')))
    continued={}
    for job in plan['jobs']:
        p=root/'jobs'/job['condition']/(job['pid']+'.json');r=s.load(p)
        if r and not r['job_done']:
            assert r['stop_reason'] in ('campaign_stopped_before_send','recovered_response_needs_repair')
            continued[job['job_id']]=s.sha(p)
    s.atomic_json(root/'resume_ready.json',dict(continued_records=continued,retained_timeout=retained,at=s.stamp()))
    s.atomic_json(out/'recovery.json',dict(passed=True,settled=fixed,retained_timeout=retained,continued_jobs=list(continued),
        completed_134_unchanged=True,no_model_calls=True,new_accounted_cny=after['spent_cny'],new_plan_sha256=new_sha))
    s.atomic_json(root/'ledger_checkpoint.json',dict(sha256=s.sha(ledger_path),at=s.stamp()))
    s.atomic_json(root/'study_state.json',dict(state='resume_ready',at=s.stamp(),completed=sum(s.load(root/'jobs'/j['condition']/(j['pid']+'.json')).get('job_done',False) for j in plan['jobs'])))
    from f14_v10_report import report
    report(cfg,plan);s.verify(cfg)
    target=s.MIRROR/'recovery_io_resume_20261113';target.mkdir(parents=True,exist_ok=True)
    for name in ('recovery.json','tests.log','completed_hashes.json'):shutil.copyfile(out/name,target/name)
    for name in ('timeout_reservations.json','resume_ready.json'):shutil.copyfile(root/name,s.MIRROR/name)
    print('RECOVERED two paid replies; retained one timeout; continued jobs',len(continued),'accounted',after['spent_cny'],flush=True)

if __name__=='__main__':main()

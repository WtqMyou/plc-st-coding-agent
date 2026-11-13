"""Close confirmed API timeouts without retries, changing no generated code or fees."""
import copy
from pathlib import Path
import shutil
import f14_v10_core as s
from f14_v10_report import audit_final,report

def main():
    cfg=s.config();root=Path(cfg['campaign_root']);plan=s.verify(cfg)
    assert not s.old.old.support.registered_process_alive(s.load(root/'active_run.json')),'Controller must exit before closing records'
    assert s.load(root/'study_state.json')['state']=='stopped'
    assert not (root/'completion.json').exists()
    out=root/'final_timeout_closure_20261113';out.mkdir(exist_ok=False)
    ledger_path=Path(cfg['budget_ledger_path']);ledger_before=ledger_path.read_bytes();ledger=s.load(ledger_path)
    for name in ('study_state.json','active_run.json','timeout_reservations.json'):
        shutil.copyfile(root/name,out/(name+'.before'))
    (out/'ledger.before.json').write_bytes(ledger_before)
    done={};pending=[]
    for job in plan['jobs']:
        path=root/'jobs'/job['condition']/(job['pid']+'.json');record=s.load(path)
        assert record and record['attempts']
        if record['job_done']:done[job['job_id']]=s.sha(path)
        else:pending.append((job,path,record))
    assert len(done)==138 and {j['job_id'] for j,_,_ in pending}=={
        'custom_minimax-m27/self-medium-06','codex_minimax-m27/self-medium-06'}
    timeout_manifest=s.load(root/'timeout_reservations.json');retained=[]
    for event in ledger['events'][s.HISTORY:]:
        if event['status']!='reserved':continue
        req=event['request'];condition,pid=req['job_id'].split('/');idx=req['candidate_index']
        private=root/'transport_private'/condition/pid/str(idx)
        diagnostic=s.load(private/'diagnostic.json')
        assert diagnostic['outcome']=='wall_deadline' and diagnostic['bytes_received']==0
        assert (private/'http_body.bin').stat().st_size==0
        retained.append(dict(request_id=event['request_id'],job_id=req['job_id'],candidate_index=idx,
            reserved_cny=event['reserved_cny'],diagnostic_sha256=s.sha(private/'diagnostic.json')))
        if event['request_id'] not in timeout_manifest['request_ids']:timeout_manifest['request_ids'].append(event['request_id'])
        target=s.MIRROR/'timeout_evidence'/event['request_id'];target.mkdir(parents=True,exist_ok=True)
        for name in ('diagnostic.json','http_body.bin'):shutil.copyfile(private/name,target/name)
    assert len(retained)==3
    closed=[]
    for job,path,record in pending:
        idx=len(record['attempts'])-1;a=record['attempts'][idx]
        event=next(e for e in retained if e['job_id']==job['job_id'] and e['candidate_index']==idx)
        assert a.get('provider_error') and not a.get('code')
        before=out/'jobs_before'/job['condition']/path.name;before.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,before)
        a['unknown_cost_reservation_cny']=event['reserved_cny']
        record.update(job_done=True,stop_reason='confirmed_timeout_no_retry_reservation_retained',best_attempt=s.select_best(record['attempts']))
        record['closure']=dict(at=s.stamp(),user_instruction='赶紧想办法完成最后两组',
            reason='Confirmed 420-second timeout with zero response bytes; retain best existing candidate and full cost reservation',
            new_generation_requests=0,candidate_limit_unchanged=True)
        s.atomic_json(path,record)
        best=record['attempts'][record['best_attempt']]
        closed.append(dict(job_id=job['job_id'],attempts=len(record['attempts']),best_candidate=best['idx']+1,
            tests_passed=best['tests_passed'],tests_total=best['tests_total'],functional_pass=best['functional_pass']))
    timeout_manifest.update(amount_cny=float(sum((s.money(e['reserved_cny']) for e in retained),s.money(0))),
        events=retained,requests_not_retried=True,new_generation_requests=0,updated_at=s.stamp())
    s.atomic_json(root/'timeout_reservations.json',timeout_manifest)
    for job,digest in done.items():
        condition,pid=job.split('/');assert s.sha(root/'jobs'/condition/(pid+'.json'))==digest
    assert ledger_path.read_bytes()==ledger_before,'Finalization must never clear, refund or change fees'
    audit=audit_final(cfg,plan);assert audit['passed'] and audit['unknown_requests_retained']==3
    audit.update(finalization='coverage complete; API timeouts retained as failed invocations',
        all_138_completed_records_unchanged=True,new_generation_requests_during_closure=0,
        unresolved_cost_reservations_cny=timeout_manifest['amount_cny'])
    s.atomic_json(root/'final_audit.json',audit)
    s.atomic_json(root/'completion.json',dict(completed=True,jobs=140,requests=len(ledger['events'])-s.HISTORY,
        accounted_cny=ledger['spent_cny'],unresolved_requests=3,unresolved_cost_reservations_cny=timeout_manifest['amount_cny'],
        final_audit_passed=True,at=s.stamp()))
    s.atomic_json(root/'study_state.json',dict(state='completed',at=s.stamp(),completed=140,
        outcome='completed_with_three_recorded_api_timeouts',unresolved_cost_reservations_cny=timeout_manifest['amount_cny'],
        error='',generation_stopped=True))
    marker=s.load(root/'active_run.json');marker.update(state='completed',finalized_at=s.stamp());s.atomic_json(root/'active_run.json',marker)
    s.atomic_json(root/'ledger_checkpoint.json',dict(sha256=s.sha(ledger_path),at=s.stamp()))
    target=s.MIRROR/'final_timeout_closure_20261113';target.mkdir(parents=True,exist_ok=True)
    proof=dict(passed=True,closed=closed,previous_completed_138_unchanged=True,original_requests_preserved=True,
        ledger_before_sha256=s.sha(out/'ledger.before.json'),ledger_after_sha256=s.sha(ledger_path),
        generation_requests_sent=0,helper_sha256=s.sha(__file__),at=s.stamp())
    s.atomic_json(out/'closure.json',proof);s.atomic_json(target/'closure.json',proof)
    text='''# V10最终两题次收尾

四组各35题、共140/140题次均已完整归档。最后两个题次均为self-medium-06，MiniMax第三候选请求等待420秒后无正文返回。

严格保留既有候选及原始记录：自研MiniMax最好通过14/23条用例，Codex MiniMax最好通过18/23条；两题均记为功能未整题通过。无人工补写答案，无额外生成请求，也没有降低通过标准。

本轮319次请求，316次已结算、3次超时费用仍按预留上界保留，合计0.589673元。项目累计计入159.535005元，含上述未知预留，仍低于420元上限。账本本次未修改，不将未知费用记为零；平台实际账单可另行核对。

完整性审计通过：原138个已完成题次记录未改变，全部请求、候选、原生编译与功能证据及费用可以逐条对应。功能成绩、编译成绩和形式状态分别统计；接口调用失败保留分母。完整覆盖已经完成，三个未知预留并不表示已确认实扣。
'''
    (s.MIRROR/'最终收尾说明.md').write_text(text,encoding='utf-8')
    summary=report(cfg,plan)
    assert summary['recorded']==140 and summary['completion_audit_passed']
    print('COMPLETED 140/140; 319 requests; 3 timeout reservations retained; no new model calls; audit passed',flush=True)

if __name__=='__main__':main()

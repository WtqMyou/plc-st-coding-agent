"""Validate three reviewed interrupted requests without inventing receipts or answers."""
import copy
import hashlib
import json
from pathlib import Path
import zipfile
import full_r8b_study as s
from full_r8b_report import metrics,markdown,report,mirror
TARGET='custom_minimax-m27/self-medium-01'
REQUEST='1448cf1d067c4f9dbff0c3e4c352cd39'
RESERVE=.125822
ALL_RESERVED=1.241276
REVIEWED={
 '03c29d15a4f94b0e8d8fe18882a50e27':dict(job='codex_deepseek-v4pro/self-hard-04',reserve=.644821,error='Upstream HTTP 504',status=504,outcome='http_error'),
 'd6269f093d5d49f0a67861e4342c32f1':dict(job='custom_deepseek-v4pro/self-hard-06',reserve=.470633,error='SSE EOF before completed response',status=200,outcome='transport_error'),
 REQUEST:dict(job=TARGET,reserve=RESERVE,error='Upstream total wall deadline exceeded; partial trace retained; no automatic retry',status=None,outcome='wall_deadline')}


def audit_records(root,plan,ledger):
    before=s.load(root/'ledger_before_study.json');assert s.prefix_ok(ledger,before)
    events=ledger['events'][s.HISTORY:];assert 1<=len(events)<=280
    keyed={(e['request']['job_id'],e['request']['candidate_index']):e for e in events};assert len(keyed)==len(events)
    unknown=[e for e in events if e['status']!='settled']
    assert len(unknown)==len(REVIEWED) and {e['request_id'] for e in unknown}==set(REVIEWED)
    for event in unknown:
        approved=REVIEWED[event['request_id']]
        assert event['status']=='reserved' and event['request']['job_id']==approved['job'] and event['request']['candidate_index']==0
        assert s.money(event['reserved_cny'])==s.money(approved['reserve'])
    records={};attempted=0;calls=0;settled=0;confirmed=s.money(0);details=[]
    cfg=s.config();problems=s.data()
    for job in plan['jobs']:
        folder=root/'jobs'/job['condition'];path=folder/(job['pid']+'.json');record=s.load(path)
        if not record:
            assert not list(folder.glob(job['pid']+'.*')),'Orphan request trace'
            continue
        attempted+=1
        assert 1<=len(record['attempts'])<=2 and record['study_plan_sha256']==s.sha(root/'study_plan.json')
        assert s.load(folder/(job['pid']+'.timing.json'))['upstream_requests_entered']==len(record['attempts'])
        if record.get('job_done'):records[job['job_id']]=s.sha(path)
        else:assert job['job_id']==TARGET,'Unexpected partial job'
        model=next(m for m in cfg['models'] if m['id']==job['model_id'])
        for idx,a in enumerate(record['attempts']):
            calls+=1;event=keyed[(job['job_id'],idx)]
            request=s.load(folder/(job['pid']+f'.request_{idx+1:02}.json'))
            assert event['phase']==s.KIND and request['model']==event['request']['model']==model['model']
            assert request['parameters']==model['parameters'] and request['max_tokens']==16384
            upper=s.money(((len(json.dumps(request['messages'],ensure_ascii=False).encode())+4096)*model['input_cny_per_million']+16384*model['output_cny_per_million'])/1e6)
            assert upper==s.money(event['reserved_cny'])<=s.money(job['first_upper_cny'] if idx==0 else job['repair_upper_cny'])
            assert a['tests_total']==len(problems[job['pid']].test_cases)
            if event['status']=='reserved':
                assert event['request_id'] in REVIEWED and idx==0 and len(record['attempts'])==1
                approved=REVIEWED[event['request_id']]
                assert a['provider_error']==approved['error'] and not a['code'] and not a['actual_model']
                assert not a['prompt_tokens'] and not a['completion_tokens'] and not a['cost_cny']
                assert not (folder/(job['pid']+'.response_01.json')).exists(),'Unexpected recovered answer'
                diagnostic=s.load(folder/(job['pid']+'.transport_01.json'))
                assert diagnostic.get('http_status')==approved['status'] and not diagnostic['completed_terminal']
                assert diagnostic['outcome']==approved['outcome'] and diagnostic['automatic_retries']==0
                continue
            response=s.load(folder/(job['pid']+f'.response_{idx+1:02}.json'))
            assert response['model']==a['actual_model']==event['metadata']['model']
            assert response['model'].casefold() in {m.casefold() for m in model['accepted_models']}
            assert response['usage']==event['metadata']['usage']
            assert a['prompt_tokens']==event['metadata']['prompt_tokens'] and a['completion_tokens']==event['metadata']['completion_tokens']
            cost=s.money((a['prompt_tokens']*model['input_cny_per_million']+a['completion_tokens']*model['output_cny_per_million'])/1e6)
            assert cost==s.money(a['cost_cny'])==s.money(event['accounted_cny']);confirmed+=cost;settled+=1
            if a['code']:
                assert hashlib.sha256(a['code'].encode()).hexdigest()==a['code_hash']
                assert s.extract_code(response['message'].get('content',''))==a['code']
            if idx:
                prior=record['attempts'][0];assert prior['code'] and not prior['provider_error']
                expected=(prior['feedback'][:4000]+'\n修复并返回完整代码，保持题面接口。').replace('\r\n','\n')
                assert any(expected in m['content'].replace('\r\n','\n') for m in request['messages'])
        details.append(dict(job_id=job['job_id'],job_done=record['job_done'],first_solved=record['first_try'],
                            solved=record['solved'],attempts=len(record['attempts']),technical_failure=job['job_id'] in {v['job'] for v in REVIEWED.values()}))
    assert calls==len(events) and s.money(s.BASELINE)+confirmed+s.money(ALL_RESERVED)==s.money(ledger['spent_cny'])
    return dict(completed_jobs=len(records),attempted_jobs=attempted,settled_requests=settled,
                unknown_requests=len(REVIEWED),actual_requests=calls,record_sha256=records,remaining_jobs=140-len(records),
                confirmed_new_cost_cny=float(confirmed),retained_unknown_cny=ALL_RESERVED,total_accounted_cny=ledger['spent_cny'],
                next_job=next((j['job_id'] for j in plan['jobs'] if j['job_id'] not in records),None),jobs=details)

def authorize(cfg,proof,private,tag):
    from stbench.billing import ledger_lock
    root=Path(cfg['campaign_root']);path=Path(cfg['budget_ledger_path']);plan=s.load(root/'study_plan.json')
    raw=path.read_bytes();assert s.sha(path)==proof['ledger_checkpoint_sha256']
    state=json.loads(raw);audit_records(root,plan,state)
    assert state['halted']=='Unconfirmed upstream result; reservation retained'
    recordpath=root/'jobs/custom_minimax-m27/self-medium-01.json';record=s.load(recordpath)
    assert not record['job_done'] and s.sha(recordpath)==proof['failed_record_before_sha256']
    after=copy.deepcopy(record);after['job_done']=True
    after['operational_closure']=dict(kind='user_authorized_transport_failure_closure',tag=tag,
         source='Host sleep interrupted request; wall deadline, no code or usage receipt',retained_reserve_cny=RESERVE,no_model_retry=True)
    entry=dict(tag=tag,at=s.stamp(),user_authorization='用户再次要求重启实验；保留三次中断请求的预留，均不补发，接续剩余22题次。',
               previous_halt=state['halted'],previous_halt_details=state.get('halt_details'),request_id=REQUEST,job_id=TARGET,retained_unknown_cny=RESERVE,
               ledger_before_sha256=proof['ledger_checkpoint_sha256'],failed_record_before_sha256=proof['failed_record_before_sha256'],
               review_checkpoint_cny=80,total_cap_cny=170,generation_response_recovered=False,original_attempt_unchanged=True)
    assert not any(x.get('tag')==tag for x in state.get('operational_recoveries',[]))
    state.setdefault('operational_recoveries',[]).append(entry)
    state['halted']=''
    state.pop('halt_details',None)
    with ledger_lock(path):
        assert path.read_bytes()==raw
        s.atomic_json(path,state)
        s.atomic_json(recordpath,after)
    assert s.load(recordpath)['attempts']==record['attempts']
    assert s.load(path)['events']==json.loads(raw)['events'],'Request fees must remain untouched'
    s.atomic_json(private/'manual_recovery.json',dict(**entry,failed_record_after_sha256=s.sha(recordpath),
                  ledger_after_sha256=s.sha(path),next_job='codex_deepseek-v4pro/self-medium-01'))
    s.checkpoint(cfg,root)

def finalize_retained(cfg,plan):
    root=Path(cfg['campaign_root']);s.verify(root);ledger=s.history(cfg,root,plan)
    assert not ledger['halted'] and s.load(root/'study_state.json')['state']=='completed'
    result=audit_records(root,plan,ledger);assert result['completed_jobs']==result['attempted_jobs']==140
    assert not (root/'release_manifest.json').exists()
    summary=report(cfg,plan)
    result.update(coverage_completed=True,billing_fully_settled=False,acceptance_passed=False,
                  final_fee_acceptance_pending=True,technical_failure_jobs=[x['job'] for x in REVIEWED.values()],source_files=plan['files'])
    s.atomic_json(root/'analysis.json',result)
    text=markdown(cfg,plan,summary)
    text+='\n## 覆盖完成，费用尚待最终结算\n\n140题次已尝试，其中3题次因HTTP504、流式提前结束或电脑睡眠导致请求超时，没有返回代码。这三次技术中断单列，保留在固定分母，不冒充模型代码错误或成功答卷；没有为该题补发请求。合计1.241276元预留继续保留，非确认实扣。确认费用、未知预留及累计计入分别记录；最终费用验收尚未完成。\n'
    text+='\n## 逐题结果\n\n|题次|首次功能通过|最终功能通过|候选数|技术故障|\n|---|---|---|---:|---|\n'
    for d in result['jobs']:text+=f"|{d['job_id']}|{d['first_solved']}|{d['solved']}|{d['attempts']}|{d['technical_failure']}|\n"
    text+='\n主实验为同一冻结配置下的四组全题对照；HTTP504、流式提前结束、睡眠超时及人工授权接续另有证据。该结果不单独证明某一种反馈的因果收益或稳定框架优势。形式截断、未决及未执行不算形式证明。\n'
    (root/'最终报告.md').write_bytes(text.encode())
    for job in plan['jobs']:
        record=s.load(root/'jobs'/job['condition']/(job['pid']+'.json'))
        for a in record['attempts']:
            native=a.get('platform_results',{}).get('codesys',{})
            if not native:continue
            assert native['source_sha256']==a['code_hash']
            assert native['platform_identity']==s.load(root/'native_preflight.json')['codesys']['positive']['platform_identity']
            for name in ('candidate.st','result.json','codesys_result.json'):
                source=Path(native['artifact_dir'])/name
                if source.exists():
                    target=root/'native_evidence'/job['condition']/job['pid']/str(a['idx'])/name
                    target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(source.read_bytes())
    mirror(root)
    files={p.relative_to(s.MIRROR).as_posix():s.sha(p) for p in s.MIRROR.rglob('*') if p.is_file()}
    s.atomic_json(root/'release_manifest.json',dict(kind=s.KIND,files=files,source_files=plan['files'],
         coverage_completed=True,billing_fully_settled=False,pending_reserve_cny=ALL_RESERVED,actual_requests=result['actual_requests']))
    mirror(root);archive=root/'验收包.zip'
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED) as z:
        for p in s.MIRROR.rglob('*'):
            if p.is_file():z.writestr('evidence/'+p.relative_to(s.MIRROR).as_posix(),p.read_bytes())
        for p in s.source_files():z.writestr('source/'+p.relative_to(s.REPO).as_posix(),p.read_bytes())
    with zipfile.ZipFile(archive) as z:assert z.testzip() is None
    s.atomic_json(root/'package_manifest.json',dict(sha256=s.sha(archive),coverage_completed=True,billing_fully_settled=False))
    mirror(root)

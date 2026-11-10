"""Explicit user-authorized operational restart at a settled full-job boundary.
Delegates generation, judging, selection and budget policy to the frozen batch-b implementation.
"""
import copy
import ctypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from datetime import datetime
sys.path.insert(0,str(Path(__file__).resolve().parent))
import full_r8b_study as s
from full_r8b_report import report,finalize

TAG='reboot_20261110'
AUTHORIZATION='用户在电脑重启后明确要求“帮我重启实验”；保留已完成题次，80元检查点不提高。'

def audit_records(root,plan,ledger):
    assert not ledger.get('halted'),'Ledger is halted; no operational restart'
    before=s.load(root/'ledger_before_study.json')
    assert s.prefix_ok(ledger,before),'Historical prefix changed'
    events=ledger['events'][s.HISTORY:]
    assert events and len(events)<=280 and all(e['status']=='settled' for e in events),'Unsettled request; do not repeat'
    keyed={(e['request']['job_id'],e['request']['candidate_index']):e for e in events}
    assert len(keyed)==len(events),'Duplicate charged candidate'
    total=s.money(0);records={};attempts=0
    for job in plan['jobs']:
        folder=root/'jobs'/job['condition'];path=folder/(job['pid']+'.json')
        record=s.load(path)
        if not record:
            assert not list(folder.glob(job['pid']+'.*')),'Orphan request trace'
            continue
        assert record['job_done'] and 1<=len(record['attempts'])<=2,'Partial job; do not repeat'
        assert record['study_plan_sha256']==s.sha(root/'study_plan.json')
        assert s.load(folder/(job['pid']+'.timing.json'))['upstream_requests_entered']==len(record['attempts'])
        model=next(m for m in s.config()['models'] if m['id']==job['model_id'])
        for idx,a in enumerate(record['attempts']):
            event=keyed[(job['job_id'],idx)]
            assert event['phase']==s.KIND
            request=s.load(folder/(job['pid']+f'.request_{idx+1:02}.json'))
            response=s.load(folder/(job['pid']+f'.response_{idx+1:02}.json'))
            assert request['model']==event['request']['model']==model['model']
            assert request['parameters']==model['parameters'] and request['max_tokens']==16384
            assert response['model']==a['actual_model']==event['metadata']['model']
            assert response['model'].casefold() in {m.casefold() for m in model['accepted_models']}
            assert response['usage']==event['metadata']['usage']
            assert a['prompt_tokens']==event['metadata']['prompt_tokens'] and a['completion_tokens']==event['metadata']['completion_tokens']
            cost=s.money((a['prompt_tokens']*model['input_cny_per_million']+a['completion_tokens']*model['output_cny_per_million'])/1e6)
            assert cost==s.money(a['cost_cny'])==s.money(event['accounted_cny'])
            upper=s.money(((len(json.dumps(request['messages'],ensure_ascii=False).encode())+4096)*model['input_cny_per_million']+16384*model['output_cny_per_million'])/1e6)
            assert upper==s.money(event['reserved_cny'])<=s.money(job['first_upper_cny'] if idx==0 else job['repair_upper_cny'])
            if a['code']:
                assert hashlib.sha256(a['code'].encode()).hexdigest()==a['code_hash']
                assert s.extract_code(response['message'].get('content',''))==a['code']
            if idx:
                prior=record['attempts'][0];assert prior['code'] and not prior['provider_error']
                feedback=(prior['feedback'][:4000]+'\n修复并返回完整代码，保持题面接口。').replace('\r\n','\n')
                assert any(feedback in m['content'].replace('\r\n','\n') for m in request['messages'])
            total+=cost;attempts+=1
        records[job['job_id']]=s.sha(path)
    assert attempts==len(events)
    assert s.money(s.BASELINE)+total==s.money(ledger['spent_cny'])
    return dict(completed_jobs=len(records),settled_requests=attempts,record_sha256=records,
                total_accounted_cny=ledger['spent_cny'],study_increment_cny=float(total),
                remaining_jobs=140-len(records),next_job=next((j['job_id'] for j in plan['jobs'] if j['job_id'] not in records),None))

def paths(cfg):
    root=Path(cfg['campaign_root'])
    return root,root/'operational_restarts'/TAG,s.MIRROR/'operational_restarts'/TAG

def audit(cfg,require_stopped=True):
    root,_,_=paths(cfg);plan=s.load(root/'study_plan.json');s.verify(root)
    assert not s.old.support.registered_process_alive(s.load(root/'active_run.json')),'Runner still active'
    state=s.load(root/'study_state.json')
    if require_stopped:
        assert state['state']=='stopped' and 'git' in state.get('error','') and 'push' in state.get('error',''),'Restart only for the reviewed publication failure'
    ledger=s.history(cfg,root,plan)
    assert s.sha(cfg['budget_ledger_path'])==s.load(root/'ledger_checkpoint.json')['sha256'],'Ledger changed after the last full-job checkpoint'
    result=audit_records(root,plan,ledger)
    assert len(s.remaining_jobs(root,plan))==result['remaining_jobs']
    return result

def copy_public(private,public):
    public.mkdir(parents=True,exist_ok=True)
    for p in private.rglob('*'):
        if p.is_file():
            destination=public/p.relative_to(private);destination.parent.mkdir(parents=True,exist_ok=True)
            content=p.read_text(encoding='utf-8');assert s.old.support.sanitize(content)==content
            destination.write_bytes(p.read_bytes())

def prepare(cfg):
    root,private,public=paths(cfg)
    assert not private.exists() and not public.exists(),'Restart evidence already exists'
    result=audit(cfg)
    private.mkdir(parents=True)
    for name in ('study_state.json','active_run.json','ledger_checkpoint.json','study_summary.json','live.stdout.log','live.stderr.log'):
        target=private/('before_'+name)
        target.write_bytes(s.old.support.sanitize((root/name).read_text(encoding='utf-8')).encode())
    raw_backup=root/'restart_private'/TAG;raw_backup.mkdir(parents=True)
    (raw_backup/'ledger_before.json').write_bytes(Path(cfg['budget_ledger_path']).read_bytes())
    s.old.native_preflight(cfg,private)
    assert s.sha(cfg['budget_ledger_path'])==s.load(root/'ledger_checkpoint.json')['sha256'],'Free preflight changed ledger'
    for backend in (s.old.support.CodesysBackend(cfg),s.old.support.OpenPLCBackend(cfg)):
        assert backend.identity()==s.load(root/'native_preflight.json')[backend.name]['positive']['platform_identity']
    result.update(at=s.stamp(),user_authorization=AUTHORIZATION,review_checkpoint_cny=80,total_cap_cny=170,
                  model_requests_during_prepare=0,study_plan_sha256=s.sha(root/'study_plan.json'),
                  ledger_checkpoint_sha256=s.sha(cfg['budget_ledger_path']),
                  controller_sha256=s.sha(__file__),tests_sha256=s.sha(s.REPO/'progress/tests/test_restart_full_r8b.py'),
                  compiler_controls_sha256=s.sha(private/'native_preflight.json'))
    s.atomic_json(private/'restart_audit.json',result)
    source=private/'source';source.mkdir()
    for p in (Path(__file__),s.REPO/'progress/tests/test_restart_full_r8b.py'):(source/p.name).write_bytes(p.read_bytes())
    (private/'接续说明.md').write_bytes(('''# 电脑重启后的已结算边界接续

用户明确要求重启实验。检查发现原进程已结束，停止原因为GitHub推送失败；已完整归档44/140题次、67次生成请求，全部已结算，累计46.999003元，无新增未知预留。已补推本地两次进度提交。

接续只执行原冻结计划中的剩余96题次，从第45题次开始，不重新生成前44题。原始模型、参数、提示、裁判、候选选择、1200秒时限和最多一次修复规则均保持，接续控制器直接调用冻结实现；源码与核对证据摘要另行登记。累计170元上限、接近80元暂停保持，不提高人工检查点。

原停止状态、日志、检查点和账本快照已保存，当前状态页可更新为运行中。仅当所有已发请求都有匹配回执和费用、所有已开始题次都完整结束、账本检查点完全一致、原生正反编译控制通过、冻结代码和已完成答卷摘要无变化、接续代码推送成功后，才允许新的模型请求。任何未结算、残留请求或部分题次都拒绝接续。

原Git发布失败仍会停止后续生成，不自动重发模型请求。本次是用户明确授权的运行恢复，不伪造80元复核通过，也不篡改原冻结入口的停止限制。
''').encode())
    copy_public(private,public)
    print('PREPARED restart:',result['completed_jobs'],'preserved,',result['remaining_jobs'],'remaining; no model requests',flush=True)

def verify_extension(cfg):
    root,private,public=paths(cfg);proof=s.load(private/'restart_audit.json')
    assert proof['controller_sha256']==s.sha(__file__)
    assert proof['tests_sha256']==s.sha(s.REPO/'progress/tests/test_restart_full_r8b.py')
    assert proof['compiler_controls_sha256']==s.sha(private/'native_preflight.json')
    assert proof==s.load(public/'restart_audit.json')
    for job_id,digest in proof['record_sha256'].items():
        condition,pid=job_id.split('/')
        assert s.sha(root/'jobs'/condition/(pid+'.json'))==digest,'Previously completed answer changed'
    return proof

def run(cfg):
    root,private,public=paths(cfg);proof=verify_extension(cfg);current=audit(cfg)
    assert current['completed_jobs']==proof['completed_jobs'] and current['settled_requests']==proof['settled_requests']
    assert not (private/'resume_environment.json').exists(),'This restart controller was already used; no implicit retry'
    head=s.ensure_pushed()
    published=subprocess.check_output(['git','show',head+':progress/tools/restart_full_r8b.py'],cwd=s.REPO)
    assert hashlib.sha256(published).hexdigest()==proof['controller_sha256']
    catalog=s.old.credential_check(cfg);assert all(catalog['selected_models'].values())
    s.old.support.no_other_runner(cfg)
    budget=s.StudyBudget(cfg['budget_ledger_path'],s.sha(root/'study_plan.json'),s.REVIEW)
    pending=s.remaining_jobs(root,s.load(root/'study_plan.json'));plan=s.load(root/'study_plan.json')
    s.atomic_json(private/'resume_environment.json',dict(at=s.stamp(),published_restart_commit=head,
                  user_authorization=AUTHORIZATION,preserved_jobs=proof['completed_jobs'],remaining_jobs=len(pending),
                  review_checkpoint_cny=80,catalog=catalog))
    copy_public(private,public)
    s.atomic_json(root/'active_run.json',dict(**s.old.support.current_process_marker(),state='running',entry='restart_full_r8b.py',restart=TAG))
    final_state='stopped';awake=False
    try:
        s.atomic_json(root/'study_state.json',dict(state='running',at=s.stamp(),next_job=current['next_job'],review_ceiling_cny=80,restart=TAG))
        report(cfg,plan);s.publish()
        if os.name=='nt':awake=bool(ctypes.windll.kernel32.SetThreadExecutionState(0x80000001))
        for job in plan['jobs']:
            if job['job_id'] not in pending:continue
            s.verify(root);verify_extension(cfg)
            assert s.sha(cfg['budget_ledger_path'])==s.load(root/'ledger_checkpoint.json')['sha256'],'Unrelated ledger mutation'
            s.history(cfg,root,plan)
            try:budget.admit_job(pending[job['job_id']])
            except s.ReviewPause as exc:
                final_state='paused_for_api_review'
                s.atomic_json(root/'study_state.json',dict(state=final_state,at=s.stamp(),next_job=job['job_id'],
                              reason=str(exc),review_ceiling_cny=80,remaining_jobs=list(pending),restart=TAG))
                break
            s.atomic_json(root/'study_state.json',dict(state='running',at=s.stamp(),current_job=job['job_id'],review_ceiling_cny=80,restart=TAG))
            report(cfg,plan)
            record=s.generate_job(cfg,root,plan,job,budget,pending);assert record['job_done']
            snapshot=s.history(cfg,root,plan);assert snapshot['events'][-1]['status']=='settled'
            pending.pop(job['job_id']);s.checkpoint(cfg,root)
            summary=report(cfg,plan);s.publish()
            print('FINISHED',job['job_id'],'records',summary['recorded'],'increment',summary['study_increment_cny'],flush=True)
        else:
            final_state='completed'
            s.atomic_json(root/'study_state.json',dict(state=final_state,at=s.stamp(),review_ceiling_cny=80,restart=TAG))
            summary=report(cfg,plan);assert summary['recorded']==140
            s.atomic_json(root/'completion.json',dict(completed=True,recorded=140,actual_requests=summary['new_events'],
                 study_increment_cny=summary['study_increment_cny'],total_accounted_cny=summary['total_accounted_cny'],ended_at=s.stamp()))
    except BaseException as exc:
        s.atomic_json(root/'study_state.json',dict(state='stopped',at=s.stamp(),error=s.old.support.sanitize(str(exc)),restart=TAG))
        if isinstance(exc,subprocess.CalledProcessError):
            s.atomic_json(private/'publication_failure.json',dict(error=s.old.support.sanitize(str(exc)),
                stderr=s.old.support.sanitize((exc.stderr or b'').decode('utf-8',errors='replace') if isinstance(exc.stderr,bytes) else (exc.stderr or '')),at=s.stamp()))
            copy_public(private,public)
        raise
    finally:
        if awake:ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
        marker=s.load(root/'active_run.json');marker.update(state=final_state,ended_at=s.stamp());s.atomic_json(root/'active_run.json',marker)
        report(cfg,plan);s.publish()
    if final_state=='completed':
        finalize(cfg,plan);s.publish();print('COMPLETED AND AUDITED',flush=True)
    elif final_state=='paused_for_api_review':print('PAUSED FOR USER API REVIEW; no automatic resume',flush=True)

if __name__=='__main__':
    if len(sys.argv)!=2 or sys.argv[1] not in ('prepare','run','check'):raise SystemExit('Usage: restart_full_r8b.py prepare|run|check')
    cfg=s.config()
    if sys.argv[1]=='prepare':prepare(cfg)
    elif sys.argv[1]=='run':run(cfg)
    else:
        verify_extension(cfg)
        root=Path(cfg['campaign_root'])
        audit_records(root,s.load(root/'study_plan.json'),s.load(cfg['budget_ledger_path']))
        print('PASS explicit restart evidence, old answers and settled receipts',flush=True)

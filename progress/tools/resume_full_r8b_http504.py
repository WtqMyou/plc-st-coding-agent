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
from full_r8b_report import report
import full_r8b_retained_http504 as retained
finalize=retained.finalize_retained

TAG='http504_20261111'
AUTHORIZATION='用户明确要求“实验已停止，检查并重启”；保留已发HTTP504请求及0.644821元预留，不重发该请求，80元检查点不提高。'

audit_records=retained.audit_records

def paths(cfg):
    root=Path(cfg['campaign_root'])
    return root,root/'operational_restarts'/TAG,s.MIRROR/'operational_restarts'/TAG

def audit(cfg,require_stopped=True):
    root,_,_=paths(cfg);plan=s.load(root/'study_plan.json');s.verify(root)
    assert not s.old.support.registered_process_alive(s.load(root/'active_run.json')),'Runner still active'
    state=s.load(root/'study_state.json')
    if require_stopped:
        assert state['state']=='stopped' and state.get('error')=='Upstream HTTP 504','Restart only for the reviewed HTTP504 failure'
    ledger=s.history(cfg,root,plan)
    assert ledger['halted']=='HTTP failure; reservation retained'
    checkpoint=s.load(root/'ledger_checkpoint.json')
    reconstructed=copy.deepcopy(ledger);reconstructed['events'].pop();reconstructed['spent_cny']=checkpoint['spent_cny'];reconstructed['halted']=''
    assert len(ledger['events'])==603 and ledger['events'][-1]['request_id']==retained.REQUEST
    encoded=json.dumps(reconstructed,ensure_ascii=False,indent=2)
    variants=(encoded.encode(),encoded.replace('\n','\r\n').encode())
    assert any(hashlib.sha256(b).hexdigest()==checkpoint['sha256'] for b in variants),'Unexpected ledger drift beyond the reviewed HTTP failure'
    result=audit_records(root,plan,ledger)
    assert result['completed_jobs']==102 and result['attempted_jobs']==103 and result['settled_requests']==151
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
    s.atomic_json(private/'native_preflight.json',s.load(root/'native_preflight.json'))
    failed=root/'jobs/codex_deepseek-v4pro/self-hard-04.json'
    (private/'before_failed_job.json').write_bytes(failed.read_bytes())
    assert s.sha(cfg['budget_ledger_path'])==s.sha(raw_backup/'ledger_before.json'),'Free checks changed ledger'
    for backend in (s.old.support.CodesysBackend(cfg),s.old.support.OpenPLCBackend(cfg)):
        assert backend.identity()==s.load(root/'native_preflight.json')[backend.name]['positive']['platform_identity']
    result.update(at=s.stamp(),user_authorization=AUTHORIZATION,review_checkpoint_cny=80,total_cap_cny=170,
                  model_requests_during_prepare=0,study_plan_sha256=s.sha(root/'study_plan.json'),
                  ledger_checkpoint_sha256=s.sha(cfg['budget_ledger_path']),
                  controller_sha256=s.sha(__file__),tests_sha256=s.sha(s.REPO/'progress/tests/test_resume_full_r8b_http504.py'),
                  compiler_controls_sha256=s.sha(private/'native_preflight.json'),
                  accounting_source_sha256=s.sha(Path(retained.__file__)),failed_record_before_sha256=s.sha(private/'before_failed_job.json'))
    s.atomic_json(private/'restart_audit.json',result)
    source=private/'source';source.mkdir()
    for p in (Path(__file__),Path(retained.__file__),s.REPO/'progress/tests/test_resume_full_r8b_http504.py'):(source/p.name).write_bytes(p.read_bytes())
    (private/'接续说明.md').write_bytes(('''# HTTP504之后的人工授权接续

用户明确要求检查并重启。当前已完整保存102/140题次，151次请求已结算；第103题次的Codex DeepSeek多泵请求返回提供方HTTP504及service unavailable，未返回代码、身份或用量，0.644821元预留继续保留。累计计入55.745711元，未到80元。

本次接续不重发这次失败请求，不将其当作模型代码错误。原失败记录、日志和账本快照保留；仅追加技术故障终止说明，将该题次作为已尝试但无代码的服务故障单列。此前102题次内容摘要保持不变，从原冻结顺序的第104题次继续，其余37题次不改变模型、提示、裁判或修复策略。

账本保留全部603条既有事件、未知预留和原恢复记录；仅登记本次用户授权并清除这一次已审查的停止标记，不退款冲销、不填造回执。若再发生新的未知费用或公共故障仍立即停止。累计170元、接近80元暂停保持，不伪造80元复核。

全部140题次覆盖完成后，提供方故障和费用未最终结算须在报告中明示。证据包可保存覆盖与现有回执核验结果，不能把保留预留当作实扣费用或宣布最终费用验收通过。
''').encode())
    copy_public(private,public)
    print('PREPARED HTTP504 restart: 102 preserved, 1 technical failure retained, 37 unstarted; no model requests',flush=True)

def verify_extension(cfg):
    root,private,public=paths(cfg);proof=s.load(private/'restart_audit.json')
    assert proof['controller_sha256']==s.sha(__file__)
    assert proof['accounting_source_sha256']==s.sha(Path(retained.__file__))
    recovery=s.load(private/'manual_recovery.json')
    if recovery:assert s.sha(root/'jobs/codex_deepseek-v4pro/self-hard-04.json')==recovery['failed_record_after_sha256']
    assert proof['tests_sha256']==s.sha(s.REPO/'progress/tests/test_resume_full_r8b_http504.py')
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
    published=subprocess.check_output(['git','show',head+':progress/tools/resume_full_r8b_http504.py'],cwd=s.REPO)
    assert hashlib.sha256(published).hexdigest()==proof['controller_sha256']
    catalog=s.old.credential_check(cfg);assert all(catalog['selected_models'].values())
    s.old.support.no_other_runner(cfg)
    retained.authorize(cfg,proof,private,TAG)
    budget=s.StudyBudget(cfg['budget_ledger_path'],s.sha(root/'study_plan.json'),s.REVIEW)
    pending=s.remaining_jobs(root,s.load(root/'study_plan.json'));plan=s.load(root/'study_plan.json')
    s.atomic_json(private/'resume_environment.json',dict(at=s.stamp(),published_restart_commit=head,
                  user_authorization=AUTHORIZATION,preserved_jobs=proof['completed_jobs'],remaining_jobs=len(pending),
                  review_checkpoint_cny=80,catalog=catalog,retained_unknown_cny=.644821))
    copy_public(private,public)
    s.atomic_json(root/'active_run.json',dict(**s.old.support.current_process_marker(),state='running',entry='resume_full_r8b_http504.py',restart=TAG))
    final_state='stopped';awake=False
    try:
        s.atomic_json(root/'study_state.json',dict(state='running',at=s.stamp(),next_job='custom_deepseek-v4pro/self-hard-04',review_ceiling_cny=80,restart=TAG))
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
    if len(sys.argv)!=2 or sys.argv[1] not in ('prepare','run','check'):raise SystemExit('Usage: resume_full_r8b_http504.py prepare|run|check')
    cfg=s.config()
    if sys.argv[1]=='prepare':prepare(cfg)
    elif sys.argv[1]=='run':run(cfg)
    else:
        verify_extension(cfg)
        root=Path(cfg['campaign_root'])
        audit_records(root,s.load(root/'study_plan.json'),s.load(cfg['budget_ledger_path']))
        print('PASS explicit HTTP504 restart, retained reserve and old answers',flush=True)

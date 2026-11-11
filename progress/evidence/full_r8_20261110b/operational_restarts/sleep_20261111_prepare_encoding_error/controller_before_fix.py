"""Explicit user-authorized restart after one reviewed sleep-interrupted request.
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
import full_r8b_retained_timeout as retained
finalize=retained.finalize_retained

TAG='sleep_20261111'
AUTHORIZATION='用户再次要求“实验已停止，检查并重启”；保留三次中断请求预留，不补发请求，80元检查点不提高。'

audit_records=retained.audit_records

def paths(cfg):
    root=Path(cfg['campaign_root'])
    return root,root/'operational_restarts'/TAG,s.MIRROR/'operational_restarts'/TAG

def audit(cfg,require_stopped=True):
    root,_,_=paths(cfg);plan=s.load(root/'study_plan.json');s.verify(root)
    assert not s.old.support.registered_process_alive(s.load(root/'active_run.json')),'Runner still active'
    state=s.load(root/'study_state.json')
    if require_stopped:
        assert state['state']=='stopped' and state.get('error')=='Upstream total wall deadline exceeded; partial trace retained; no automatic retry','Restart only for the reviewed host-sleep timeout'
    ledger=s.history(cfg,root,plan)
    assert ledger['halted']=='Unconfirmed upstream result; reservation retained'
    checkpoint=s.load(root/'ledger_checkpoint.json')
    reconstructed=copy.deepcopy(ledger);reconstructed['events'].pop();reconstructed['spent_cny']=checkpoint['spent_cny'];reconstructed['halted']='';reconstructed.pop('halt_details',None)
    assert len(ledger['events'])==623 and ledger['events'][-1]['request_id']==retained.REQUEST
    encoded=json.dumps(reconstructed,ensure_ascii=False,indent=2)
    variants=(encoded.encode(),encoded.replace('\n','\r\n').encode())
    assert any(hashlib.sha256(b).hexdigest()==checkpoint['sha256'] for b in variants),'Unexpected ledger drift beyond the reviewed timeout'
    result=audit_records(root,plan,ledger)
    assert result['completed_jobs']==117 and result['attempted_jobs']==118 and result['settled_requests']==169
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
    for name in ('live.stdout.log','live.stderr.log'):
        source=root/'runtime_restarts/stream_eof_20261111'/name
        (private/('active_runtime_'+name)).write_bytes(s.old.support.sanitize(source.read_text(encoding='utf-8')).encode())
    raw_backup=root/'restart_private'/TAG;raw_backup.mkdir(parents=True)
    (raw_backup/'ledger_before.json').write_bytes(Path(cfg['budget_ledger_path']).read_bytes())
    s.atomic_json(private/'native_preflight.json',s.load(root/'native_preflight.json'))
    failed=root/'jobs/custom_minimax-m27/self-medium-01.json'
    (private/'before_failed_job.json').write_bytes(failed.read_bytes())
    assert s.sha(cfg['budget_ledger_path'])==s.sha(raw_backup/'ledger_before.json'),'Free checks changed ledger'
    for backend in (s.old.support.CodesysBackend(cfg),s.old.support.OpenPLCBackend(cfg)):
        assert backend.identity()==s.load(root/'native_preflight.json')[backend.name]['positive']['platform_identity']
    result.update(at=s.stamp(),user_authorization=AUTHORIZATION,review_checkpoint_cny=80,total_cap_cny=170,
                  model_requests_during_prepare=0,study_plan_sha256=s.sha(root/'study_plan.json'),
                  ledger_checkpoint_sha256=s.sha(cfg['budget_ledger_path']),
                  controller_sha256=s.sha(__file__),tests_sha256=s.sha(s.REPO/'progress/tests/test_resume_full_r8b_sleep.py'),
                  compiler_controls_sha256=s.sha(private/'native_preflight.json'),
                  accounting_source_sha256=s.sha(Path(retained.__file__)),failed_record_before_sha256=s.sha(private/'before_failed_job.json'))
    s.atomic_json(private/'restart_audit.json',result)
    source=private/'source';source.mkdir()
    for p in (Path(__file__),Path(retained.__file__),s.REPO/'progress/tests/test_resume_full_r8b_sleep.py'):(source/p.name).write_bytes(p.read_bytes())
    (private/'接续说明.md').write_bytes(('''# 睡眠中断后的人工接续

用户要求重启实验。已归档117题次；第118题次自研MiniMax self-medium-01没有收到响应正文及用量回执。Windows系统记录显示11:59因Button or Lid进入睡眠，13:10恢复；请求墙钟耗时4342.656秒，唤醒后触发原420秒请求总时限。没有证据表明该请求完整返回，不能拼造代码或费用。

此次0.125822元预留保留，三次未知预留合计1.241276元，累计计入58.192297元不冲销，623条历史事件不变。保留原117题次，仅将此次部分题次按技术中断终止，不补发。从原计划第119题次接续其余22题次。模型、提示、裁判、修复规则、80元暂停及170元上限不变；休眠期间的实际墙钟时长保留，不改成420秒。

此前停止时的GitHub推送也失败，已补推本地进度提交。旧冻结入口、旧停止现场、答卷及回执继续保留。仅清除此已审查的停止标记；新的未知费用或故障仍立即停止。最终报告把三次技术中断及未知预留单列，不能宣称费用完全结算。后台运行需保持开机联网，避免合盖、睡眠或手动休眠。
''').encode())
    copy_public(private,public)
    print('PREPARED sleep restart: 117 preserved, third interruption retained, 22 unstarted; no model requests',flush=True)

def verify_extension(cfg):
    root,private,public=paths(cfg);proof=s.load(private/'restart_audit.json')
    assert proof['controller_sha256']==s.sha(__file__)
    assert proof['accounting_source_sha256']==s.sha(Path(retained.__file__))
    recovery=s.load(private/'manual_recovery.json')
    if recovery:assert s.sha(root/'jobs/custom_minimax-m27/self-medium-01.json')==recovery['failed_record_after_sha256']
    assert proof['tests_sha256']==s.sha(s.REPO/'progress/tests/test_resume_full_r8b_sleep.py')
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
    published=subprocess.check_output(['git','show',head+':progress/tools/resume_full_r8b_sleep_20261111.py'],cwd=s.REPO)
    assert hashlib.sha256(published).hexdigest()==proof['controller_sha256']
    catalog=s.old.credential_check(cfg);assert all(catalog['selected_models'].values())
    s.old.support.no_other_runner(cfg)
    retained.authorize(cfg,proof,private,TAG)
    budget=s.StudyBudget(cfg['budget_ledger_path'],s.sha(root/'study_plan.json'),s.REVIEW)
    pending=s.remaining_jobs(root,s.load(root/'study_plan.json'));plan=s.load(root/'study_plan.json')
    s.atomic_json(private/'resume_environment.json',dict(at=s.stamp(),published_restart_commit=head,
                  user_authorization=AUTHORIZATION,preserved_jobs=proof['completed_jobs'],remaining_jobs=len(pending),
                  review_checkpoint_cny=80,catalog=catalog,retained_unknown_cny=1.241276))
    copy_public(private,public)
    s.atomic_json(root/'active_run.json',dict(**s.old.support.current_process_marker(),state='running',entry='resume_full_r8b_sleep_20261111.py',restart=TAG))
    final_state='stopped';awake=False
    try:
        s.atomic_json(root/'study_state.json',dict(state='running',at=s.stamp(),next_job='codex_deepseek-v4pro/self-medium-01',review_ceiling_cny=80,restart=TAG))
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
        finalize(cfg,plan);s.publish();print('COVERAGE COMPLETED; THREE INTERRUPTED REQUEST RECEIPTS STILL PENDING',flush=True)
    elif final_state=='paused_for_api_review':print('PAUSED FOR USER API REVIEW; no automatic resume',flush=True)

if __name__=='__main__':
    if len(sys.argv)!=2 or sys.argv[1] not in ('prepare','run','check'):raise SystemExit('Usage: resume_full_r8b_sleep_20261111.py prepare|run|check')
    cfg=s.config()
    if sys.argv[1]=='prepare':prepare(cfg)
    elif sys.argv[1]=='run':run(cfg)
    else:
        verify_extension(cfg)
        root=Path(cfg['campaign_root'])
        audit_records(root,s.load(root/'study_plan.json'),s.load(cfg['budget_ledger_path']))
        print('PASS explicit sleep restart, three retained reserves and old answers',flush=True)

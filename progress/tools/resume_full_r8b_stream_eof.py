"""Explicit user-authorized restart after one reviewed incomplete stream.
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
import full_r8b_retained_service_faults as retained
finalize=retained.finalize_retained

TAG='stream_eof_20261111'
AUTHORIZATION='用户再次要求“实验已停止，检查并重启”；保留两次服务故障预留，不补发请求，80元检查点不提高。'

audit_records=retained.audit_records

def paths(cfg):
    root=Path(cfg['campaign_root'])
    return root,root/'operational_restarts'/TAG,s.MIRROR/'operational_restarts'/TAG

def audit(cfg,require_stopped=True):
    root,_,_=paths(cfg);plan=s.load(root/'study_plan.json');s.verify(root)
    assert not s.old.support.registered_process_alive(s.load(root/'active_run.json')),'Runner still active'
    state=s.load(root/'study_state.json')
    if require_stopped:
        assert state['state']=='stopped' and state.get('error')=='SSE EOF before completed response','Restart only for the reviewed incomplete stream'
    ledger=s.history(cfg,root,plan)
    assert ledger['halted']=='Unconfirmed upstream result; reservation retained'
    checkpoint=s.load(root/'ledger_checkpoint.json')
    reconstructed=copy.deepcopy(ledger);reconstructed['events'].pop();reconstructed['spent_cny']=checkpoint['spent_cny'];reconstructed['halted']='';reconstructed.pop('halt_details',None)
    assert len(ledger['events'])==613 and ledger['events'][-1]['request_id']==retained.REQUEST
    encoded=json.dumps(reconstructed,ensure_ascii=False,indent=2)
    variants=(encoded.encode(),encoded.replace('\n','\r\n').encode())
    assert any(hashlib.sha256(b).hexdigest()==checkpoint['sha256'] for b in variants),'Unexpected ledger drift beyond the reviewed HTTP failure'
    result=audit_records(root,plan,ledger)
    assert result['completed_jobs']==110 and result['attempted_jobs']==111 and result['settled_requests']==160
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
        source=root/'runtime_restarts/http504_20261111'/name
        (private/('active_runtime_'+name)).write_bytes(s.old.support.sanitize(source.read_text(encoding='utf-8')).encode())
    raw_backup=root/'restart_private'/TAG;raw_backup.mkdir(parents=True)
    (raw_backup/'ledger_before.json').write_bytes(Path(cfg['budget_ledger_path']).read_bytes())
    s.atomic_json(private/'native_preflight.json',s.load(root/'native_preflight.json'))
    failed=root/'jobs/custom_deepseek-v4pro/self-hard-06.json'
    (private/'before_failed_job.json').write_bytes(failed.read_bytes())
    assert s.sha(cfg['budget_ledger_path'])==s.sha(raw_backup/'ledger_before.json'),'Free checks changed ledger'
    for backend in (s.old.support.CodesysBackend(cfg),s.old.support.OpenPLCBackend(cfg)):
        assert backend.identity()==s.load(root/'native_preflight.json')[backend.name]['positive']['platform_identity']
    result.update(at=s.stamp(),user_authorization=AUTHORIZATION,review_checkpoint_cny=80,total_cap_cny=170,
                  model_requests_during_prepare=0,study_plan_sha256=s.sha(root/'study_plan.json'),
                  ledger_checkpoint_sha256=s.sha(cfg['budget_ledger_path']),
                  controller_sha256=s.sha(__file__),tests_sha256=s.sha(s.REPO/'progress/tests/test_resume_full_r8b_stream_eof.py'),
                  compiler_controls_sha256=s.sha(private/'native_preflight.json'),
                  accounting_source_sha256=s.sha(Path(retained.__file__)),failed_record_before_sha256=s.sha(private/'before_failed_job.json'))
    s.atomic_json(private/'restart_audit.json',result)
    source=private/'source';source.mkdir()
    for p in (Path(__file__),Path(retained.__file__),s.REPO/'progress/tests/test_resume_full_r8b_stream_eof.py'):(source/p.name).write_bytes(p.read_bytes())
    (private/'接续说明.md').write_bytes(('''# 流式连接提前结束后的人工接续

用户再次要求检查并重启。已归档110题次；此前的HTTP504服务故障已单列。第111题次自研DeepSeek self-hard-06在收到700个事件后连接提前结束，仅含response.created、in_progress及推理增量，无输出正文、无完整结束对象、无用量回执。保留原始175902字节及摘要，不从推理片段拼造代码。

此次0.470633元预留继续保留，与此前HTTP504的0.644821元合计1.115454元。累计计入56.951486元不冲销，全部613条既有事件不改。原110题次保持，仅将此次部分题次按技术故障终止留档，不补发这次调用。从原计划第112题次接续其余29题次；模型、提示、裁判、修复规则及80元暂停不变。

仅清除此用户已明确审查的停止标记并追加授权。今后出现任何新的未知请求仍立即停止；不自动滚动接受其他异常。最终报告把两次服务故障、固定分母和保留预留单列，不能宣布费用完全结算或把服务故障冒充代码错误。旧冻结入口、旧停止现场、已完成答卷及回执保留。
''').encode())
    copy_public(private,public)
    print('PREPARED stream EOF restart: 110 preserved, second technical failure retained, 29 unstarted; no model requests',flush=True)

def verify_extension(cfg):
    root,private,public=paths(cfg);proof=s.load(private/'restart_audit.json')
    assert proof['controller_sha256']==s.sha(__file__)
    assert proof['accounting_source_sha256']==s.sha(Path(retained.__file__))
    recovery=s.load(private/'manual_recovery.json')
    if recovery:assert s.sha(root/'jobs/custom_deepseek-v4pro/self-hard-06.json')==recovery['failed_record_after_sha256']
    assert proof['tests_sha256']==s.sha(s.REPO/'progress/tests/test_resume_full_r8b_stream_eof.py')
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
    published=subprocess.check_output(['git','show',head+':progress/tools/resume_full_r8b_stream_eof.py'],cwd=s.REPO)
    assert hashlib.sha256(published).hexdigest()==proof['controller_sha256']
    catalog=s.old.credential_check(cfg);assert all(catalog['selected_models'].values())
    s.old.support.no_other_runner(cfg)
    retained.authorize(cfg,proof,private,TAG)
    budget=s.StudyBudget(cfg['budget_ledger_path'],s.sha(root/'study_plan.json'),s.REVIEW)
    pending=s.remaining_jobs(root,s.load(root/'study_plan.json'));plan=s.load(root/'study_plan.json')
    s.atomic_json(private/'resume_environment.json',dict(at=s.stamp(),published_restart_commit=head,
                  user_authorization=AUTHORIZATION,preserved_jobs=proof['completed_jobs'],remaining_jobs=len(pending),
                  review_checkpoint_cny=80,catalog=catalog,retained_unknown_cny=1.115454))
    copy_public(private,public)
    s.atomic_json(root/'active_run.json',dict(**s.old.support.current_process_marker(),state='running',entry='resume_full_r8b_stream_eof.py',restart=TAG))
    final_state='stopped';awake=False
    try:
        s.atomic_json(root/'study_state.json',dict(state='running',at=s.stamp(),next_job='codex_deepseek-v4pro/self-hard-06',review_ceiling_cny=80,restart=TAG))
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
        finalize(cfg,plan);s.publish();print('COVERAGE COMPLETED; TWO SERVICE RECEIPTS STILL PENDING',flush=True)
    elif final_state=='paused_for_api_review':print('PAUSED FOR USER API REVIEW; no automatic resume',flush=True)

if __name__=='__main__':
    if len(sys.argv)!=2 or sys.argv[1] not in ('prepare','run','check'):raise SystemExit('Usage: resume_full_r8b_stream_eof.py prepare|run|check')
    cfg=s.config()
    if sys.argv[1]=='prepare':prepare(cfg)
    elif sys.argv[1]=='run':run(cfg)
    else:
        verify_extension(cfg)
        root=Path(cfg['campaign_root'])
        audit_records(root,s.load(root/'study_plan.json'),s.load(cfg['budget_ledger_path']))
        print('PASS explicit stream EOF restart, two retained reserves and old answers',flush=True)

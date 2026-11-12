"""Finalize the completed free replay; strict Path ledger locking, no model generation."""
import hashlib
from pathlib import Path
import zipfile
import recover_f14_v5_string_20261112 as recovery

s=recovery.s
ROOT=recovery.ROOT
PRIVATE=recovery.PRIVATE


def main():
    cfg=s.config();plan=s.verify(cfg);proof=recovery.RAW_LOAD(PRIVATE/'recovery_plan.json')
    ledger_path=Path(cfg['budget_ledger_path'])
    if recovery.RAW_LOAD(ROOT/'completion.json').get('judge_amendment')==recovery.TAG:
        print('Already completed; no requests or charges repeated',flush=True);return
    for rel,digest in proof['source_files'].items():assert s.sha(s.REPO/rel)==digest
    for rel,digest in proof['original_job_files'].items():assert s.sha(ROOT/'jobs'/rel)==digest
    assert s.sha(ledger_path)==proof['ledger_sha256']
    initial_audit=recovery.RAW_LOAD(PRIVATE/'final_audit_before_recovery_marker.json')
    assert initial_audit['passed'] and initial_audit['requests']==42 and initial_audit['jobs']==24
    overlays={}
    for job in plan['jobs']:
        raw_path=ROOT/'jobs'/job['condition']/(job['pid']+'.json')
        effective_path=PRIVATE/'effective_jobs'/job['condition']/(job['pid']+'.json')
        record=recovery.RAW_LOAD(effective_path);assert record['job_done'] and record['judge_amendment']==recovery.TAG
        overlays[raw_path]=effective_path
    def load(path):return recovery.RAW_LOAD(overlays.get(Path(path),Path(path)))
    s.load=load
    audit=recovery.reporting.audit_final(cfg,plan)
    audit.update(judge_amendment=recovery.TAG,new_model_calls=0,original_job_files_unchanged=True,
        free_replay_seconds=initial_audit['free_replay_seconds'],finalizer_sha256=s.sha(__file__))
    before=recovery.RAW_LOAD(ledger_path)
    with recovery.ledger_lock(ledger_path):
        assert s.sha(ledger_path)==proof['ledger_sha256']
        current=recovery.RAW_LOAD(ledger_path)
        current.setdefault('recoveries',[]).append(dict(reason='close_verified_v5_string_byte_judge_failure',at=s.stamp(),
            recovery_plan_sha256=s.sha(PRIVATE/'recovery_plan.json'),finalizer_sha256=s.sha(__file__),previous_halt=current['halted'],
            events_unchanged=1183,spent_cny_unchanged=112.728371,new_model_calls=0))
        current['halted']='';current.pop('halt_details',None)
        assert current['events']==before['events'] and current['spent_cny']==before['spent_cny'] and current['limit_cny']==210
        s.atomic_json(ledger_path,current)
    audit['ledger_sha256']=s.sha(ledger_path)
    s.atomic_json(ROOT/'final_audit.json',audit)
    s.atomic_json(ROOT/'completion.json',dict(completed=True,jobs=24,requests=42,accounted_cny=112.728371,
        at=s.stamp(),judge_amendment=recovery.TAG,new_model_calls=0))
    s.atomic_json(ROOT/'study_state.json',dict(state='completed',at=s.stamp(),completed=24,judge_amendment=recovery.TAG,new_model_calls=0))
    marker=recovery.RAW_LOAD(ROOT/'active_run.json');marker.update(state='completed',recovered_at=s.stamp(),judge_amendment=recovery.TAG)
    s.atomic_json(ROOT/'active_run.json',marker)
    s.atomic_json(ROOT/'ledger_checkpoint.json',dict(sha256=s.sha(ledger_path),at=s.stamp()))
    s.atomic_json(PRIVATE/'finalization.json',dict(passed=True,finalizer_sha256=s.sha(__file__),ledger_events_unchanged=True,
        original_job_files_unchanged=True,new_model_calls=0,all_attempts_reconciled=42,
        resumed_after='Free replay finished; original bookkeeping called ledger_lock with str instead of Path; fee ledger was untouched'))
    recovery.copy_public()
    summary=recovery.reporting.report(cfg,plan)
    summary.update(judge_amendment=recovery.TAG,effective_records='operational_restarts/'+recovery.TAG+'/effective_jobs',new_model_calls=0)
    note='\n判题接续完成：42次模型请求原已结算，免费复验现有答卷后覆盖24/24题次，没有追加模型请求。字符串BYTE转换采用真实CODESYS仿真确认的0基字节索引；课程原字符视图保留，超出已建模范围单列未决。原始答卷、提示、响应、费用和冻结裁判均保留，修正后的派生记录见operational_restarts/'+recovery.TAG+'/effective_jobs。\n'
    for folder in (ROOT,s.MIRROR):
        s.atomic_json(folder/'status.json',summary)
        for name in ('实验状态.md','最终报告.md'):
            path=folder/name
            if path.exists():path.write_text(path.read_text(encoding='utf-8')+note,encoding='utf-8')
        path=folder/'status.html';path.write_text(path.read_text(encoding='utf-8').replace('</pre>',note+'</pre>'),encoding='utf-8')
    with zipfile.ZipFile(s.MIRROR/'验收包.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for path in s.MIRROR.rglob('*'):
            if path.is_file() and path.suffix!='.zip':archive.write(path,path.relative_to(s.MIRROR).as_posix())
    print('COMPLETED 24/24; 42 settled requests; new model calls 0; cumulative 112.728371',flush=True)


if __name__=='__main__':main()

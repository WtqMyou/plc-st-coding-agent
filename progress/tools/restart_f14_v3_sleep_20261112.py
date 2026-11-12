"""User-authorized sleep recovery; immutable raw records, no request replay."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile
import f14_v3_core as s
import f14_v3_study as driver
import f14_v3_report as reporting
from stbench.billing import ledger_lock

TAG='sleep_20261112_1604'
EVENTS=929
SPENT=87.047346
RAW_LOAD=s.load
RAW_VERIFY=s.verify
RAW_REPORT=reporting.report

def paths(cfg):
    root=Path(cfg['campaign_root'])
    return root,root/'operational_restarts'/TAG,s.MIRROR/'operational_restarts'/TAG

def effective_record(raw,closure):
    assert raw['job_id']==closure['job_id'] and not raw['job_done']
    result=copy.deepcopy(raw)
    result.update(job_done=True,stop_reason='sleep_interruption_no_retry',operational_interruption=True,
        interrupted_stop_reason=raw['stop_reason'],original_record_sha256=closure['original_record_sha256'],
        closure_reason='Windows host sleep; no completed response reconstructed and no request repeated')
    return result

def copy_public(cfg):
    _,private,public=paths(cfg);public.mkdir(parents=True,exist_ok=True)
    for p in private.rglob('*'):
        if p.is_file() and p.name!='ledger_before_recovery.json':
            value=p.read_text(encoding='utf-8');assert s.sanitize(value)==value
            target=public/p.relative_to(private);target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(p.read_bytes())

def prepare(cfg):
    root,private,_=paths(cfg);assert not private.exists(),'Never overwrite restart evidence'
    plan=RAW_VERIFY(cfg);state=RAW_LOAD(root/'study_state.json')
    assert state['state']=='stopped'
    s.old.old.support.no_other_runner(cfg)
    ledger=RAW_LOAD(cfg['budget_ledger_path']);assert s.sha(cfg['budget_ledger_path'])==RAW_LOAD(root/'ledger_checkpoint.json')['sha256']
    assert (len(ledger['events']),ledger['spent_cny'],ledger['limit_cny'],ledger['halted'])==(EVENTS,SPENT,210,'ProviderError: Codex CLI timeout')
    records={};closures={};remaining=[]
    for job in plan['jobs']:
        p=root/'jobs'/job['condition']/(job['pid']+'.json');record=RAW_LOAD(p)
        if not record:
            assert not list(p.parent.glob(job['pid']+'.*')),'Orphan request must be reviewed'
            remaining.append(job);continue
        records[job['job_id']]=s.sha(p)
        if record['job_done']:continue
        assert record['stop_reason'] in ('provider_error','campaign_stopped_before_send')
        for a in record['attempts']:
            if a.get('provider_error'):assert 'timeout' in a['provider_error'].lower() or 'deadline' in a['provider_error'].lower()
        closures[job['job_id']]=dict(job_id=job['job_id'],original_record_sha256=s.sha(p))
    unknown=[e for e in ledger['events'][s.HISTORY:] if e['status']=='reserved']
    assert len(records)==12 and len(closures)==7 and len(remaining)==128 and len(unknown)==6
    assert all(e['request']['job_id'] in closures for e in unknown)
    private.mkdir(parents=True)
    power_script="Get-WinEvent -FilterHashtable @{LogName='System';StartTime=(Get-Date '2026-11-12T15:50:00');Id=42,107,1} -ErrorAction Stop | Where-Object {$_.ProviderName -match 'Kernel-Power|Power-Troubleshooter'} | Select-Object Id,RecordId,ProviderName,@{Name='time_utc';Expression={$_.TimeCreated.ToUniversalTime().ToString('o')}} | ConvertTo-Json -Depth 4"
    events=subprocess.run([shutil.which('pwsh') or 'powershell.exe','-NoProfile','-NonInteractive','-Command',power_script],capture_output=True,text=True,encoding='utf-8',timeout=20,check=True)
    power=json.loads(events.stdout);power=power if isinstance(power,list) else [power]
    assert any(e['Id']==42 for e in power) and any(e['Id']==1 for e in power)
    s.atomic_json(private/'power_events.json',power)
    for event in unknown:
        req=event['request'];diag=root/'transport_private'/req['job_id']/str(req['candidate_index'])/'diagnostic.json'
        details=RAW_LOAD(diag);assert details['outcome']=='wall_deadline' and not details.get('completed_terminal',False)
        target=private/'transport_diagnostics'/req['job_id']/(str(req['candidate_index'])+'.json')
        target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(diag.read_bytes())
    (private/'ledger_before_recovery.json').write_bytes(Path(cfg['budget_ledger_path']).read_bytes())
    for name in ('study_state.json','active_run.json','ledger_checkpoint.json'):(private/('before_'+name)).write_bytes((root/name).read_bytes())
    for key,digest in records.items():
        condition,pid=key.split('/');source=root/'jobs'/condition/(pid+'.json')
        target=private/'original_records'/condition/(pid+'.json');target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(source.read_bytes())
        assert s.sha(target)==digest
    remaining_upper=sum((s.money(j['first_upper_cny'])+s.money(j['repair_upper_cny']) for j in remaining),s.money(0))
    assert s.money(SPENT)+remaining_upper<=s.money(210)
    note='''# 2026-11-12睡眠中断接续

Windows系统日志显示15:56进入睡眠，16:04恢复，造成6个在途请求失去完整回执。原5个正常完成题次与7个中断题次、18个模型请求全部保留；6项未知预留不冲销，不重发请求。7份原始状态记录逐字节保留，另存派生的中断终止记录，统计时计入分母并保留已经得到的候选与测试结果。

从原冻结计划其余128个未开始题次接续。模型、提示、题库、裁判、规范化、修复机会、并发上限8、单模型上限4与累计210元保护均不变。当前累计87.047346元、929条事件不清零。用户已要求“重启实验”，本次只解除已核实的睡眠故障停止标记，增加接续证据；任何新的未知费用或工具故障仍停止。

原jobs记录保持故障发生时的状态；effective_jobs中的7份派生记录用于生命周期统计，attempts及得分与原记录完全一致。最终报告单列服务中断和未结算预留，不将其当作正常模型完成。运行时请保持开机联网，避免合盖或休眠。
'''
    (private/'接续说明.md').write_text(note,encoding='utf-8')
    proof=dict(kind=TAG,user_authorization='重启实验',at=s.stamp(),plan_sha256=s.sha(root/'study_plan.json'),
        ledger_before_sha256=s.sha(cfg['budget_ledger_path']),initial_events=EVENTS,initial_spent_cny=SPENT,
        preserved_records=records,closures=closures,unstarted_jobs=[j['job_id'] for j in remaining],
        remaining_worst_cny=float(remaining_upper),worst_total_cny=float(s.money(SPENT)+remaining_upper),
        retained_reservations=[dict(request_id=e['request_id'],job_id=e['request']['job_id'],reserved_cny=e['reserved_cny']) for e in unknown],
        power_events_sha256=s.sha(private/'power_events.json'),
        source_sha256={str(p.relative_to(s.REPO)).replace('\\','/'):s.sha(p) for p in (Path(__file__),s.REPO/'progress/tests/test_restart_f14_v3_sleep.py')})
    s.atomic_json(private/'restart_audit.json',proof)
    s.atomic_json(root/'execution_amendment.json',dict(restart=TAG,proof_sha256=s.sha(private/'restart_audit.json'),not_replaying_requests=True))
    copy_public(cfg)
    print('PREPARED restart: preserve 12 records; resume 128; worst cumulative',proof['worst_total_cny'],flush=True)

def verify_extension(cfg):
    root,private,_=paths(cfg);proof=RAW_LOAD(private/'restart_audit.json')
    assert proof and s.sha(root/'study_plan.json')==proof['plan_sha256']
    assert s.sha(private/'power_events.json')==proof['power_events_sha256']
    for name,digest in proof['source_sha256'].items():assert s.sha(s.REPO/name)==digest,'Restart code changed'
    for key,digest in proof['preserved_records'].items():
        condition,pid=key.split('/');assert s.sha(root/'jobs'/condition/(pid+'.json'))==digest,'Original answer changed'
    return proof

def install(cfg):
    root,private,_=paths(cfg);proof=verify_extension(cfg)
    overlays={root/'jobs'/key.split('/')[0]/(key.split('/')[1]+'.json'):closure for key,closure in proof['closures'].items()}
    def load(path):
        value=RAW_LOAD(path)
        if Path(path) in overlays:
            assert s.sha(path)==overlays[Path(path)]['original_record_sha256']
            return effective_record(value,overlays[Path(path)])
        return value
    def verify(current):verify_extension(current);return RAW_VERIFY(current)
    s.load=load;s.verify=verify
    driver.report=report
    reporting.audit_final=audit_final

def report(cfg,plan):
    root,private,_=paths(cfg);summary=RAW_REPORT(cfg,plan);proof=RAW_LOAD(private/'restart_audit.json')
    summary.update(interrupted_jobs=len(proof['closures']),normal_completed=summary['recorded']-len(proof['closures']),restart=TAG)
    note='\n睡眠接续：7个题次按中断终止单列，原始记录未改，已有候选及得分保留；6项未知预留不冲销，不补发。其余128个题次按冻结方案接续。\n'
    for folder in (root,s.MIRROR):
        s.atomic_json(folder/'status.json',summary)
        p=folder/'实验状态.md';p.write_text(p.read_text(encoding='utf-8')+note,encoding='utf-8')
        p=folder/'status.html';p.write_text(p.read_text(encoding='utf-8').replace('</pre>',note+'</pre>'),encoding='utf-8')
    for key in proof['closures']:
        condition,pid=key.split('/');target=s.MIRROR/'effective_jobs'/condition/(pid+'.json')
        s.atomic_json(target,s.load(root/'jobs'/condition/(pid+'.json')))
    copy_public(cfg)
    if summary['state']['state']=='completed':
        (s.MIRROR/'最终报告.md').write_text((root/'实验状态.md').read_text(encoding='utf-8'),encoding='utf-8')
        with zipfile.ZipFile(s.MIRROR/'验收包.zip','w',zipfile.ZIP_DEFLATED) as archive:
            for p in s.MIRROR.rglob('*'):
                if p.is_file() and p.suffix!='.zip':archive.write(p,p.relative_to(s.MIRROR).as_posix())
    return summary

def audit_final(cfg,plan):
    root,private,_=paths(cfg);ledger=RAW_LOAD(cfg['budget_ledger_path']);proof=RAW_LOAD(private/'restart_audit.json')
    events=ledger['events'][s.HISTORY:];linked={(e['request']['job_id'],e['request']['candidate_index']):e for e in events}
    retained={e['request_id'] for e in proof['retained_reservations']};attempts=0
    assert len(linked)==len(events)<=280 and s.prefix_ok(ledger,RAW_LOAD(root/'ledger_before_study.json'))
    for job in plan['jobs']:
        folder=root/'jobs'/job['condition'];record=s.load(folder/(job['pid']+'.json'))
        assert record['job_done'] and record['best_attempt']==s.select_best(record['attempts'])
        for index,a in enumerate(record['attempts']):
            event=linked[(job['job_id'],index)]
            if event['status']=='reserved':assert event['request_id'] in retained and a['provider_error']
            else:
                assert s.money(a['cost_cny'])==s.money(event['accounted_cny'])
                assert a['actual_model']==event['metadata']['model']
                assert all(a[k]==event['metadata'][k] for k in ('prompt_tokens','completion_tokens'))
                assert (folder/(job['pid']+f'.response_{index+1:02}.json')).is_file()
            assert (folder/(job['pid']+f'.request_{index+1:02}.json')).is_file()
            if a['code']:
                raw=(folder/(job['pid']+f'.raw_candidate_{index+1:02}.st')).read_bytes().decode()
                normalized,edits=s.normalize(raw);assert normalized==a['code'] and edits==a['format_edits']
                assert (folder/(job['pid']+f'.candidate_{index+1:02}.st')).read_bytes()==normalized.encode()
                assert hashlib.sha256(normalized.encode()).hexdigest()==a['code_hash']
            attempts+=1
    assert attempts==len(events) and len([e for e in events if e['status']=='reserved'])==6
    return dict(passed=True,jobs=140,attempts=attempts,cases_per_arm=946,interrupted_jobs=7,retained_unknown_requests=6,
        all_new_requests_settled=False,original_records_unchanged=True,ledger_sha256=s.sha(cfg['budget_ledger_path']),total_accounted_cny=ledger['spent_cny'])

def run(cfg):
    root,private,_=paths(cfg);proof=verify_extension(cfg);RAW_VERIFY(cfg)
    s.old.ensure_pushed();s.credentials.load_credentials(cfg);catalog=s.credentials.catalog(cfg,'secondary')
    if (private/'activation.json').exists():
        activation=RAW_LOAD(private/'activation.json');ledger=RAW_LOAD(cfg['budget_ledger_path'])
        assert len(ledger['events'])==EVENTS and not ledger['halted'] and s.sha(cfg['budget_ledger_path'])==activation['ledger_after_sha256'],'A new failure needs its own review; never replay requests'
    else:
        assert s.sha(cfg['budget_ledger_path'])==proof['ledger_before_sha256']
        with ledger_lock(Path(cfg['budget_ledger_path'])):
            ledger=RAW_LOAD(cfg['budget_ledger_path']);before=copy.deepcopy(ledger)
            assert ledger['halted']=='ProviderError: Codex CLI timeout' and len(ledger['events'])==EVENTS
            ledger.setdefault('recoveries',[]).append(dict(reason=TAG,user_authorization='重启实验',proof_sha256=s.sha(private/'restart_audit.json'),
                events_preserved=EVENTS,spent_cny_unchanged=SPENT,unknown_requests_retained=6,old_requests_retried=False))
            ledger['halted']='';ledger.pop('halt_details',None)
            assert ledger['events']==before['events'] and ledger['spent_cny']==before['spent_cny'] and ledger['limit_cny']==210
            s.atomic_json(Path(cfg['budget_ledger_path']),ledger)
        s.atomic_json(private/'activation.json',dict(at=s.stamp(),catalog=catalog,ledger_after_sha256=s.sha(cfg['budget_ledger_path'])))
    s.atomic_json(root/'ledger_checkpoint.json',dict(sha256=s.sha(cfg['budget_ledger_path']),at=s.stamp(),restart=TAG))
    copy_public(cfg);install(cfg);driver.publish();driver.live(cfg,resume=True)

def main():
    p=argparse.ArgumentParser();p.add_argument('command',choices=('prepare','check','live'));args=p.parse_args();cfg=s.config()
    if args.command=='prepare':prepare(cfg)
    elif args.command=='check':verify_extension(cfg);RAW_VERIFY(cfg);print('PASS sleep recovery signatures and original 12 records')
    else:run(cfg)

if __name__=='__main__':main()

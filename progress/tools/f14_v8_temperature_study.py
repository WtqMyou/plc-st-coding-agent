"""Freeze, execute and audit a single autonomous model repair, bounded by four new requests."""
from concurrent.futures import ThreadPoolExecutor
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from html import escape
import f14_v8_temperature_core as s
from f14_v8_temperature_budget import Coordinator,authorize,KIND,BASELINE,HISTORY,TOTAL
from f14_v6_report import serve
sys.path.insert(0,str(s.PACK))
from policy import BOUNDARY_REVIEW


def verify(cfg):
    root=Path(cfg['campaign_root']);plan=s.load(root/'study_plan.json');prepared=s.load(root/'prepared.json')
    assert s.sha(root/'study_plan.json')==prepared['plan_sha256']
    assert s.sha(root/'validation.json')==prepared['validation_sha256']
    assert plan['files']=={p.relative_to(s.REPO).as_posix():s.sha(p) for p in s.files()}
    assert plan['release_files']=={p.relative_to(s.RELEASE).as_posix():s.sha(p) for p in s.RELEASE.rglob('*') if p.is_file()}
    assert s.old.old.support.CodesysBackend(cfg).identity()==plan['native_identity']
    assert s.sha(cfg['credential_rotation']['secondary_dpapi_path'])==plan['secondary_cipher_sha256']
    assert s.sha(root/'authorization_proof.json')==plan['authorization_proof_sha256']
    return plan


def report(cfg,plan):
    root=Path(cfg['campaign_root']);s.MIRROR.mkdir(parents=True,exist_ok=True)
    job=plan['jobs'][0];record=s.load(root/'jobs'/job['condition']/(s.PID+'.json'))
    ledger=s.load(cfg['budget_ledger_path']);state=s.load(root/'study_state.json')
    best=record['attempts'][record['best_attempt']] if record.get('best_attempt') is not None else {}
    events=ledger['events'][HISTORY:]
    achieved=bool(record.get('job_done') and best.get('functional_pass') and best.get('native_pass') and best.get('verification_status')!='violated')
    summary=dict(state=state,scope='targeted_autonomous_temperature_repair',achieved=achieved,requests=len(events),maximum_requests=4,
        seed_functional_cases='35/37',functional_cases_passed=best.get('tests_passed',0),functional_cases_total=37,
        native_status=best.get('judge',{}).get('platform_results',{}).get('codesys',{}).get('status','not_run'),
        formal_status=best.get('verification_status','not_run'),accounted_cny=ledger['spent_cny'],
        new_accounted_cny=float(s.money(ledger['spent_cny'])-s.money(BASELINE)),
        new_unsettled_reservations=sum(e['status']=='reserved' for e in events),updated_at=s.stamp())
    lines=['# 温控题Agent自主修复验证','',f"状态：{state.get('state','prepared')}；新请求{len(events)}/4；当前最佳功能{summary['functional_cases_passed']}/37。",
        f"累计计入{ledger['spent_cny']:.6f}/210元，本轮新增计入{summary['new_accounted_cny']:.6f}元（运行时包含在途预留）。",'',
        '输入为原公开题面、V6原模型35/37答卷及安全执行反馈，补充通用严格时间比较与TON语义。没有提供手工修正版、参考程序或隐藏期望值。',
        '这是单题定向补充验证，与旧六题四组实验分开记录。功能通过、原生编译与形式状态分别报告。','',
        '| 新候选 | CODESYS | 功能用例 | 形式状态 | 本次计入/元 |','| --- | --- | ---: | --- | ---: |']
    for a in record.get('attempts',[]):lines.append(f"| {a['idx']+1} | {a['native_pass']} | {a['tests_passed']}/37 | {a['verification_status']} | {a['cost_cny']:.6f} |")
    lines+=['',f"本轮最坏新增预留{plan['worst_reservation_cny']:.6f}元。空正文、截断及调用故障不自动补发；重复候选停止；身份、费用或公共工具异常停止。",'',
        f"自主修复目标已达到：{achieved}。",'原始答卷、原V6成绩和所有历史费用保留。']
    text='\n'.join(lines)+'\n'
    s.atomic_json(root/'status.json',summary);(root/'实验状态.md').write_text(text,encoding='utf-8')
    page='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta http-equiv="refresh" content="10"><meta name="viewport" content="width=device-width,initial-scale=1"><title>温控自主修复</title><style>body{font:16px/1.7 system-ui;max-width:1100px;margin:30px auto;padding:0 20px;background:#f3f6fb;color:#172b42}pre{white-space:pre-wrap;background:white;padding:24px;border-radius:12px}</style><h1>温控题Agent自主修复</h1><pre>'+escape(text)+'</pre></html>'
    (root/'status.html').write_text(page,encoding='utf-8')
    for name in ('study_plan.json','validation.json','authorization_proof.json','prepared.json','study_state.json','budget_authorization.json','run_environment.json','status.json','status.html','实验状态.md','final_audit.json','completion.json'):
        if (root/name).is_file():shutil.copyfile(root/name,s.MIRROR/name)
    if record.get('job_done') or state.get('state')=='stopped':
        for p in (root/'jobs').rglob('*'):
            if p.is_file() and p.suffix!='.tmp':
                data=p.read_bytes();assert s.sanitize(data.decode('utf-8'))==data.decode('utf-8')
                target=s.MIRROR/'jobs'/p.relative_to(root/'jobs');target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
    return summary


def prepare(cfg):
    root=Path(cfg['campaign_root']);assert not root.exists(),'Do not overwrite prior requests'
    ledger=Path(cfg['budget_ledger_path']);before=ledger.read_bytes();state=json.loads(before)
    assert (state['limit_cny'],state['spent_cny'],len(state['events']),bool(state.get('halted')))==(TOTAL,BASELINE,HISTORY,False)
    s.parent.verify(s.parent.config());s.old.old.support.no_other_runner(cfg)
    source_path=s.REPO/'progress/evidence/f14_v6_public_pilot_20261112/jobs/custom_deepseek-v4pro/public-medium-04.json'
    previous=s.load(source_path);seed=previous['attempts'][previous['best_attempt']]
    assert seed['tests_passed']==35 and seed['native_pass'] and seed['code_hash']==hashlib.sha256(seed['code'].encode()).hexdigest()
    judged=s.run_stage(seed['code'],s.PID,'functional',30)
    assert judged['result']['tests_passed']==35 and judged['result']['tests_total']==37
    task=s.tasks()[s.PID];user=s.load(s.RELEASE/'agent_inputs.json')[s.PID]['user']
    interface=[{key:v[key] for key in ('name','data_type','direction','fields') if key in v} for v in task['variables']]
    system=cfg['system']+'\nCanonical public interface:\n'+json.dumps(interface,ensure_ascii=False)+'\n'+BOUNDARY_REVIEW
    messages=[dict(role='system',content=system),dict(role='user',content=user),dict(role='assistant',content=seed['code']),
        dict(role='user',content=judged['feedback']+'\n'+BOUNDARY_REVIEW)]
    s.atomic_json(s.PACK/'initial_messages.json',dict(messages=messages))
    s.atomic_json(s.PACK/'seed_metadata.json',dict(original_job_path=source_path.relative_to(s.REPO).as_posix(),original_job_sha256=s.sha(source_path),
        original_candidate_index=seed['idx'],original_candidate_sha256=seed['code_hash'],original_user_sha256=hashlib.sha256(user.encode()).hexdigest(),
        seed_judge_source='V7 corrected RETURN judge',seed_result_sha256=hashlib.sha256(json.dumps(judged,ensure_ascii=False,sort_keys=True).encode()).hexdigest(),
        seed_cases_passed=35,developer_patch_used=False,reference_answer_used=False))
    root.mkdir(parents=True);(root/'ledger_before_study.json').write_bytes(before)
    s.atomic_json(root/'seed_evaluation.json',judged)
    p=subprocess.run([sys.executable,'-B','-X','utf8','-m','unittest','discover','-s','progress/tests','-p','test_f14_v8_temperature.py','-v'],
        cwd=s.REPO,capture_output=True,text=True,encoding='utf-8',timeout=120)
    (root/'free_tests.log').write_text(p.stdout+p.stderr,encoding='utf-8');assert p.returncode==0,p.stderr
    model=cfg['models'][0]
    upper=s.money((65536*model['input_cny_per_million']+16384*model['output_cny_per_million'])/1e6)
    assert len(json.dumps(messages,ensure_ascii=False).encode())+4096<=65536
    worst=4*upper;assert s.money(BASELINE)+worst<=s.money(TOTAL)
    condition='custom_'+model['id'];job=dict(pid=s.PID,framework='custom',model_id=model['id'],condition=condition,job_id=condition+'/'+s.PID,
        first_upper_cny=float(upper),repair_upper_cny=float(upper),initial_user_sha256=hashlib.sha256(user.encode()).hexdigest())
    proof=dict(user_instruction='让它自主生成并通过这个修正',existing_total_cap_cny=210,scope='one-task autonomous repair of V6 seed, at most four new requests',
        initial_spent_cny=BASELINE,initial_event_count=HISTORY,all_history_and_unknown_reservations_retained=True,developer_source_and_oracle_not_provided=True)
    s.atomic_json(root/'authorization_proof.json',proof)
    plan=dict(kind=KIND,jobs=[job],planned=1,maximum_requests=4,total_cap_cny=TOTAL,worst_reservation_cny=float(worst),
        message_byte_limit=61440,request_input_byte_bound=65536,max_output_tokens=16384,
        initial_spent_cny=BASELINE,initial_event_count=HISTORY,initial_ledger_sha256=s.sha(ledger),
        files={p.relative_to(s.REPO).as_posix():s.sha(p) for p in s.files()},
        release_files={p.relative_to(s.RELEASE).as_posix():s.sha(p) for p in s.RELEASE.rglob('*') if p.is_file()},
        native_identity=s.old.old.support.CodesysBackend(cfg).identity(),authorization_proof_sha256=s.sha(root/'authorization_proof.json'),
        secondary_cipher_sha256=s.sha(cfg['credential_rotation']['secondary_dpapi_path']))
    s.atomic_json(root/'study_plan.json',plan)
    s.atomic_json(root/'validation.json',dict(passed=True,external_model_calls=0,tests=p.stdout+p.stderr,seed_source_verified=True,expected_values_excluded=True))
    s.atomic_json(root/'prepared.json',dict(plan_sha256=s.sha(root/'study_plan.json'),validation_sha256=s.sha(root/'validation.json')))
    s.atomic_json(root/'study_state.json',dict(state='prepared',at=s.stamp()))
    assert ledger.read_bytes()==before
    report(cfg,plan);print('PREPARED one autonomous repair; at most 4 requests; reserve',float(worst),'cumulative worst',float(s.money(BASELINE)+worst),flush=True)


def audit(cfg,plan):
    root=Path(cfg['campaign_root']);job=plan['jobs'][0];folder=root/'jobs'/job['condition'];record=s.load(folder/(s.PID+'.json'))
    ledger=s.load(cfg['budget_ledger_path']);before=s.load(root/'ledger_before_study.json');events=ledger['events'][HISTORY:]
    assert s.parent.prefix_ok(ledger,before) and ledger['limit_cny']==210
    assert record['job_done'] and len(events)==len(record['attempts'])<=4
    assert len({e['request']['candidate_index'] for e in events})==len(events)
    for a in record['attempts']:
        event=next(e for e in events if e['request']['candidate_index']==a['idx'])
        assert event['phase']==KIND and event['status']=='settled' and event['request']['job_id']==job['job_id']
        assert s.money(event['accounted_cny'])==s.money(a['cost_cny'])
        assert a['actual_model']==event['metadata']['model']
        if a['code']:
            raw=(folder/(s.PID+f".raw_candidate_{a['idx']+1:02}.st")).read_bytes().decode()
            fixed,edits=s.normalize(raw);assert fixed==a['code'] and edits==a['format_edits']
            native=a['judge'].get('platform_results',{}).get('codesys',{})
            if native.get('status') in ('passed','failed'):assert native['source_sha256']==a['code_hash']
    return dict(passed=True,new_requests=len(events),all_new_requests_settled=True,original_history_preserved=True,
        autonomous_candidate_provenance=True,developer_patch_used=False,raw_and_normalized_code_preserved=True,
        accounted_cny=ledger['spent_cny'],ledger_sha256=s.sha(cfg['budget_ledger_path']))


def publish():
    assert not subprocess.check_output(['git','diff','--cached','--name-only'],cwd=s.REPO)
    subprocess.run(['git','add','--',s.MIRROR.relative_to(s.REPO).as_posix()],cwd=s.REPO,check=True,capture_output=True)
    if subprocess.run(['git','diff','--cached','--quiet'],cwd=s.REPO).returncode:
        subprocess.run(['git','commit','-q','-m','chore: archive autonomous temperature repair evidence'],cwd=s.REPO,check=True,capture_output=True)
    subprocess.run(['git','-c','http.version=HTTP/1.1','-c','http.sslBackend=openssl','push','origin','main'],cwd=s.REPO,check=True,capture_output=True,timeout=45)


def live(cfg):
    root=Path(cfg['campaign_root']);plan=verify(cfg)
    assert s.load(root/'study_state.json')['state']=='prepared'
    s.old.old.support.no_other_runner(cfg);s.old.ensure_pushed()
    binding=s.credentials.load_credentials(cfg);catalog=s.credentials.catalog(cfg,'secondary')
    approval=authorize(cfg['budget_ledger_path'],(root/'ledger_before_study.json').read_bytes(),s.sha(root/'study_plan.json'),s.sha(root/'authorization_proof.json'))
    s.atomic_json(root/'budget_authorization.json',approval)
    s.atomic_json(root/'run_environment.json',dict(started_at=s.stamp(),secondary_key_sha256=binding['secondary'],catalog=catalog,automatic_retries=0))
    budget=Coordinator(cfg['budget_ledger_path'],dict(plan,sha256=s.sha(root/'study_plan.json'),ledger_before=str(root/'ledger_before_study.json')))
    job=plan['jobs'][0];awake=False
    s.atomic_json(root/'active_run.json',dict(**s.old.old.support.current_process_marker(),state='running',entry='f14_v8_temperature_study.py'))
    s.atomic_json(root/'study_state.json',dict(state='running',at=s.stamp()))
    try:
        if os.name=='nt':awake=bool(ctypes.windll.kernel32.SetThreadExecutionState(0x80000001))
        with ThreadPoolExecutor(max_workers=1) as pool:
            future=pool.submit(s.generate_job,cfg,root,plan,job,budget.view(job['job_id']),{},factory=s.credentials.provider_factory)
            while not future.done():report(cfg,plan);time.sleep(3)
            record=future.result()
        assert record['job_done'],'Partial evidence; inspection required, never resend automatically'
        verify(cfg);budget.finish(job['job_id']);result=audit(cfg,plan)
        s.atomic_json(root/'final_audit.json',result)
        s.atomic_json(root/'study_state.json',dict(state='completed',at=s.stamp()))
        summary=report(cfg,plan)
        s.atomic_json(root/'completion.json',dict(completed=True,target_achieved=summary['achieved'],new_requests=result['new_requests'],at=s.stamp()))
        print('COMPLETED autonomous repair:',summary['achieved'],'functional',summary['functional_cases_passed'],'/37; requests',result['new_requests'],flush=True)
    except BaseException as exc:
        budget.halt(s.sanitize(type(exc).__name__+': '+str(exc)))
        s.atomic_json(root/'study_state.json',dict(state='stopped',at=s.stamp(),error=s.sanitize(str(exc))));raise
    finally:
        if awake:ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
        marker=s.load(root/'active_run.json');marker.update(state=s.load(root/'study_state.json')['state'],ended_at=s.stamp());s.atomic_json(root/'active_run.json',marker)
        report(cfg,plan);publish()


if __name__=='__main__':
    cfg=s.config();command=sys.argv[1] if len(sys.argv)>1 else 'check'
    if command=='prepare':prepare(cfg)
    elif command=='live':live(cfg)
    elif command=='check':verify(cfg);print('PASS frozen autonomous-repair source and budget')
    elif command=='serve':serve(cfg,8891)
    else:raise SystemExit('prepare/check/live/serve')

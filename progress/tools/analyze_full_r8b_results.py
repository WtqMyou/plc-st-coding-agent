"""Read-only analysis of frozen batch-b records; output only to a separate analysis folder."""
from collections import Counter
from datetime import datetime
import hashlib
import json
from pathlib import Path
import sys
import zipfile

sys.path.insert(0,str(Path(__file__).resolve().parent))
import resume_full_r8b_sleep_20261111 as restart
import full_r8b_report as report
s=restart.s
OUT=s.REPO/'progress/evidence/full_r8b_analysis_20261111'

def native_ok(a):
    return a.get('platform_results',{}).get('codesys',{}).get('status')=='passed'

def functional_ok(a):
    return bool(a['compiles'] and native_ok(a) and a['tests_total'] and a['tests_passed']==a['tests_total'])

def trigger(a):
    if a['verification_status']=='violated':return 'formal_violation'
    if not a['compiles'] or not native_ok(a):return 'compile_interface'
    return 'functional_failed'

def category(record,a):
    if record['solved']:return 'functional_pass'
    error=a.get('provider_error','')
    if error.startswith('Generation incomplete/empty:'):return 'generation_incomplete'
    if error:return 'technical_interruption'
    if a.get('judge',{}).get('evidence_metadata',{}).get('classification')=='unsupported_modeling':return 'unsupported_modeling'
    if not a['compiles'] or not native_ok(a):return 'compile_interface'
    return 'functional_failed'

def analyze():
    cfg=s.config();root=Path(cfg['campaign_root']);ledgerpath=Path(cfg['budget_ledger_path'])
    ledger_before=ledgerpath.read_bytes();plan=s.load(root/'study_plan.json')
    s.verify(root);restart.verify_extension(cfg);ledger=s.history(cfg,root,plan)
    assert s.load(root/'study_state.json')['state']=='completed'
    assert not s.old.support.registered_process_alive(s.load(root/'active_run.json'))
    audit=restart.audit_records(root,plan,ledger)
    assert audit['completed_jobs']==audit['attempted_jobs']==140 and audit['actual_requests']==202
    stored=s.load(root/'analysis.json');assert stored['record_sha256']==audit['record_sha256']
    assert stored['coverage_completed'] and not stored['billing_fully_settled'] and not stored['acceptance_passed']
    manifest=s.load(root/'release_manifest.json')
    assert manifest==s.load(s.MIRROR/'release_manifest.json')
    for name,digest in manifest['files'].items():
        assert s.sha(root/name)==digest==s.sha(s.MIRROR/name),name
    package=s.load(root/'package_manifest.json')
    assert s.sha(root/'验收包.zip')==package['sha256']==s.sha(s.MIRROR/'验收包.zip')
    with zipfile.ZipFile(root/'验收包.zip') as archive:assert archive.testzip() is None
    summary=report.metrics(cfg,plan);assert summary['rows']==s.load(root/'study_summary.json')['rows']
    data=s.data();records={};details=[];formal_examples=[];repairs=[];overruns=[]
    identity=s.load(root/'native_preflight.json')['codesys']['positive']['platform_identity']
    for job in plan['jobs']:
        folder=root/'jobs'/job['condition'];rec=s.load(folder/(job['pid']+'.json'));records[job['job_id']]=rec
        best=next(a for a in rec['attempts'] if a['idx']==rec['best_attempt'])
        assert functional_ok(best)==bool(rec['solved'])
        timing=s.load(folder/(job['pid']+'.timing.json'))
        if timing['wall_seconds']>1200:overruns.append(dict(job=job['job_id'],wall_seconds=timing['wall_seconds']))
        for a in rec['attempts']:
            native=a.get('platform_results',{}).get('codesys',{})
            if native:assert native['source_sha256']==a['code_hash'] and native['platform_identity']==identity
            if a['code']:assert hashlib.sha256(a['code'].encode()).hexdigest()==a['code_hash']
            if a.get('judge',{}).get('model_check',{}).get('executed'):assert functional_ok(a)
            if a['verification_status']=='violated':
                violations=a['judge']['model_check']['violations']
                outside=job['pid']=='public-hard-04' and any(
                    snap.get('enqueue') and snap.get('dequeue') for v in violations for snap in v['trace'])
                formal_examples.append(dict(job=job['job_id'],candidate=a['idx'],spec_ids=[v['id'] for v in violations],
                    outside_declared_input_contract=bool(outside),selected=best['idx']==a['idx'],
                    next_status=rec['attempts'][-1]['verification_status'],next_tests_passed=rec['attempts'][-1]['tests_passed'],
                    tests_total=a['tests_total'],feedback_in_repair=len(rec['attempts'])==2))
        if len(rec['attempts'])==2:
            first,second=rec['attempts'];assert first['code'] and not first['provider_error']
            assert first.get('judge',{}).get('evidence_metadata',{}).get('classification') not in ('unsupported_modeling','tool_error')
            request=s.load(folder/(job['pid']+'.request_02.json'))
            assert any(first['code'].replace('\r\n','\n') in m['content'].replace('\r\n','\n') for m in request['messages'])
            repairs.append(dict(job=job['job_id'],trigger=trigger(first),new_functional_success=bool(rec['solved'] and not rec['first_try']),
                second_functional_pass=functional_ok(second),selected_candidate=rec['best_attempt']))
        details.append(dict(job=job['job_id'],pid=job['pid'],title=data[job['pid']].title,condition=job['condition'],
            difficulty=data[job['pid']].difficulty,source=data[job['pid']].source,first_solved=rec['first_try'],
            final_solved=rec['solved'],complete_code=rec['complete_code'],first_codesys=native_ok(rec['attempts'][0]),
            final_codesys=native_ok(best),first_tests=rec['attempts'][0]['tests_passed'],final_tests=best['tests_passed'],
            tests_total=best['tests_total'],selected_candidate=best['idx'],attempts=len(rec['attempts']),
            formal=best['verification_status'],category=category(rec,best),wall_seconds=timing['wall_seconds']))
    rows=[]
    for row in summary['rows']:
        condition=row['condition'];jobs=[d for d in details if d['condition']==condition]
        rs=[r for r in repairs if r['job'].startswith(condition+'/')]
        errors=Counter(a['provider_error'] for key,rec in records.items() if key.startswith(condition+'/') for a in rec['attempts'] if a['provider_error'])
        extra=dict(failure_categories=dict(Counter(d['category'] for d in jobs)),repair_triggers=dict(Counter(r['trigger'] for r in rs)),
            repair_gains_by_trigger=dict(Counter(r['trigger'] for r in rs if r['new_functional_success'])),generation_errors=dict(errors),
            functional_pass_without_recorded_formal_violation=sum(d['final_solved'] and d['formal']!='violated' for d in jobs),
            repair_requests=len(rs),difficulty={level:dict(total=sum(d['difficulty']==level for d in jobs),
                solved=sum(d['difficulty']==level and d['final_solved'] for d in jobs)) for level in ('easy','medium','hard')})
        assert sum(d['first_solved'] for d in jobs)==row['first_solved']
        assert sum(d['final_solved'] for d in jobs)==row['solved']
        assert sum(d['final_tests'] for d in jobs)==row['tests_passed']
        assert sum(d['tests_total'] for d in jobs)==1214
        rows.append(dict(row,**extra))
    paired={}
    for model in ('deepseek-v4pro','minimax-m27'):
        left='custom_'+model;right='codex_'+model
        paired[model]={key:[pid for pid in data if predicate(bool(records[left+'/'+pid]['solved']),bool(records[right+'/'+pid]['solved']))]
            for key,predicate in (('both',lambda a,b:a and b),('custom_only',lambda a,b:a and not b),
                                  ('codex_only',lambda a,b:not a and b),('neither',lambda a,b:not a and not b))}
    conditions=[r['condition'] for r in rows]
    all_failed=[dict(pid=pid,title=data[pid].title) for pid in data if all(not records[c+'/'+pid]['solved'] for c in conditions)]
    confirmed=sum((s.money(r['confirmed_cost_cny']) for r in rows),s.money(0))
    assert confirmed==s.money(audit['confirmed_new_cost_cny'])
    assert s.money(s.BASELINE)+confirmed+s.money(audit['retained_unknown_cny'])==s.money(ledger['spent_cny'])
    ended=datetime.fromisoformat(s.load(root/'completion.json')['ended_at'])
    started=datetime.fromisoformat(s.load(root/'run_environment.json')['started_at'])
    result=dict(batch=s.KIND,data_version='v1.3-review-r8',judge_version='v1.3-judge-r7',
        coverage_completed=True,fees_fully_settled=False,model_calls_during_analysis=0,rows=rows,jobs=details,
        repairs=repairs,formal_examples=formal_examples,paired=paired,all_four_failed=all_failed,over_1200_seconds=overruns,
        pending_fee_events=[dict(request_id=e['request_id'],job=e['request']['job_id'],reserved_cny=e['reserved_cny'],
            created_at=e['created_at']) for e in ledger['events'][s.HISTORY:] if e['status']=='reserved'],
        totals=dict(tasks=140,assertions=4856,requests=audit['actual_requests'],settled_requests=audit['settled_requests'],
            unknown_requests=audit['unknown_requests'],first_solved=sum(r['first_solved'] for r in rows),
            final_solved=sum(r['solved'] for r in rows),repair_requests=len(repairs),
            first_codesys=sum(r['first_codesys'] for r in rows),final_codesys=sum(r['final_codesys'] for r in rows),
            complete_code=sum(r['complete_code'] for r in rows),first_assertions_passed=sum(r['first_tests_passed'] for r in rows),
            functional_pass_without_recorded_formal_violation=sum(r['functional_pass_without_recorded_formal_violation'] for r in rows),
            repair_gains=sum(r['new_functional_success'] for r in repairs),
            repair_triggers=dict(Counter(r['trigger'] for r in repairs)),
            repair_gains_by_trigger=dict(Counter(r['trigger'] for r in repairs if r['new_functional_success'])),
            final_assertions_passed=sum(r['tests_passed'] for r in rows),formal_statuses=dict(Counter(d['formal'] for d in details)),
            actual_formal_checks=sum(r['formal_attempts'] for r in rows),confirmed_new_cost_cny=float(confirmed),
            new_reserved_unknown_cny=audit['retained_unknown_cny'],historical_reserved_unknown_cny=summary['historical_unknown_reserved_cny'],
            study_accounted_increment_cny=summary['study_increment_cny'],total_accounted_cny=ledger['spent_cny'],
            task_wall_seconds=sum(d['wall_seconds'] for d in details),campaign_elapsed_seconds=(ended-started).total_seconds()),
        input_sha256={name:s.sha(root/name) for name in ('study_plan.json','study_summary.json','analysis.json','最终报告.md','release_manifest.json','package_manifest.json')},
        package_sha256=package['sha256'],record_sha256=audit['record_sha256'],tool_sha256=s.sha(__file__))
    assert ledger_before==ledgerpath.read_bytes(),'Analysis must never mutate the canonical ledger'
    return result

if __name__=='__main__':
    result=analyze()
    if sys.argv[1:]==['--check']:
        assert s.load(OUT/'statistics.json')==result
        delivery=s.load(OUT/'delivery_manifest.json')
        for name,digest in delivery.get('files',{}).items():assert s.sha(OUT/name)==digest
        print('PASS 140 records, original release hashes, 202 request events, analysis and fee decomposition')
    elif not sys.argv[1:]:
        OUT.mkdir(parents=True,exist_ok=True);s.atomic_json(OUT/'statistics.json',result)
        print(json.dumps(result['totals'],ensure_ascii=False))
    else:raise SystemExit('Usage: analyze_full_r8b_results.py [--check]')

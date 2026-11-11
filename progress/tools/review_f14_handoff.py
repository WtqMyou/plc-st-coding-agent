"""Analyze the isolated F1.4 handoff without modifying the active dataset or fee ledger."""
from collections import Counter
import hashlib
import json
from pathlib import Path
import sys
import zipfile
sys.path.insert(0,str(Path(__file__).resolve().parent))
import full_r8b_study as s

ARCHIVE=s.REPO/'11.11包/STBench_F1.4_课程原题与13题合并_交付包.zip'
REVIEW=Path('E:/PLC_Dev/evidence/incoming_reviews/stbench_f14_20261111')
SOURCE=REVIEW/'source/STBench_F1.4'
OUT=s.REPO/'progress/evidence/f14_handoff_review_20261111'

def signature(p):
    return [[v['name'],v['data_type'],v['direction']] for v in p['variables']]

def inspect():
    sha=s.sha(ARCHIVE)
    assert sha=='23805581237f6da70586b26dd55899619d917310c76561b00569851819bf0952'
    with zipfile.ZipFile(ARCHIVE) as z:
        for item in z.infolist():
            if not item.is_dir():
                relative=Path(*Path(item.filename).parts[1:])
                assert (SOURCE/relative).read_bytes()==z.read(item)
    manifest=s.load(SOURCE/'冻结清单.json')
    assert len(manifest['sha256'])==274
    for name,digest in manifest['sha256'].items():assert s.sha(SOURCE/name)==digest,name
    cfg=s.config();root=Path(cfg['campaign_root']);s.verify(root)
    protected=s.load(REVIEW/'results/baseline_protection.json');ledger=s.load(cfg['budget_ledger_path'])
    assert s.sha(cfg['budget_ledger_path'])==protected['ledger_sha256']
    assert s.sha(root/'study_plan.json')==protected['old_plan_sha256']
    assert s.sha(root/'验收包.zip')==protected['old_package_sha256']
    old=s.data();new={p.stem:s.load(p) for p in SOURCE.glob('datasets/*/*.json')}
    assert len(new)==35 and set(new)==set(old)
    index=s.load(SOURCE/'sources/index.json');bank=s.load(SOURCE/'sources/课程原题.json')
    prompts=s.load(SOURCE/'agent_inputs.json');rows=[];prompt_rows=[];new_fields=Counter()
    for pid,p in sorted(new.items()):
        prior=old[pid].to_dict();kind='public' if pid.startswith('public-') else 'selfmade'
        ref=SOURCE/'datasets'/kind/'tests'/(pid+'.reference.st')
        rows.append(dict(pid=pid,title=p['title'],original_live_cases=len(prior['test_cases']),new_cases=len(p['test_cases']),
            changed_fields=[k for k in ('requirements','variables','specs','test_cases') if prior.get(k)!=p.get(k)],
            interface_changed=signature(prior)!=signature(p),old_interface=signature(prior),new_interface=signature(p),
            new_dataset_sha256=s.sha(SOURCE/'datasets'/kind/(pid+'.json')),new_reference_sha256=s.sha(ref)))
        if pid.startswith('public-'):
            level,i,lang=index['records'][pid]['json_pointer'].strip('/').split('/')
            raw=bank[level][int(i)][lang];assert raw==prompts[pid]['user']==p['raw_text']
            assert hashlib.sha256(raw.encode()).hexdigest()==prompts[pid]['sha256']
            request=s.load(root/'jobs/custom_deepseek-v4pro'/(pid+'.request_01.json'))
            actual=next(m['content'] for m in request['messages'] if m['role']=='user')
            prompt_rows.append(dict(pid=pid,course_sha256=prompts[pid]['sha256'],
                old_user_sha256=hashlib.sha256(actual.encode()).hexdigest(),
                unchanged_ignoring_newlines=raw.replace('\r\n','\n')==actual.replace('\r\n','\n')))
        for case in p['test_cases']:
            for key in ('group','expected_any','scan_interval_ms'):
                if case.get(key) not in (None,'',[]):new_fields[key]+=1
    scores=s.load(SOURCE/'evidence/full_run.json')
    assert sum(r['passed'] for rows in scores.values() for r in rows)==946
    assert sum(r['total'] for rows in scores.values() for r in rows)==946
    traces=s.load(SOURCE/'review/trace_audit.json')
    for tag in ('quick','full'):
        text=(REVIEW/'results'/('verify_'+tag+'.stdout.log')).read_text(encoding='utf-8')
        assert 'course originals 20/20' in text and 'functional 946/946' in text
        assert not (REVIEW/'results'/('verify_'+tag+'.stderr.log')).read_bytes()
    native=s.load(REVIEW/'results/native_spotchecks.json');keyed={r['pid']:r for r in native['checks']}
    assert keyed['positive-control']['status']=='passed' and keyed['negative-control']['status']=='failed'
    assert keyed['public-easy-04']['status']==keyed['public-medium-02']['status']=='passed'
    assert keyed['public-hard-04']['status']=='failed'
    for pid in ('public-easy-04','public-hard-04','public-medium-02'):
        ref=(SOURCE/'datasets/public/tests'/(pid+'.reference.st')).read_text(encoding='utf-8')
        assert hashlib.sha256(ref.encode()).hexdigest()==keyed[pid]['source_sha256']
    controls=s.load(SOURCE/'review/f14_public_checks.json')
    mapping={'conveyor':('public-hard-02','custom_deepseek-v4pro',1),
             'recipe':('public-hard-03','custom_deepseek-v4pro',0),
             'arm_one_step':('public-hard-05','custom_deepseek-v4pro',1),
             'arm_restart':('public-hard-05','codex_deepseek-v4pro',0)}
    for name,(pid,condition,idx) in mapping.items():
        raw=(SOURCE/'review/fixtures/agent_9772562'/(name+'.st')).read_bytes()
        assert raw==s.load(root/'jobs'/condition/(pid+'.json'))['attempts'][idx]['code'].encode()
        assert hashlib.sha256(raw).hexdigest()==controls['archived_candidates'][name]['sha256']
    return dict(version='STBench-F1.4',archive_sha256=sha,manifest_files_verified=274,
        reference_functional_passed=946,reference_functional_total=946,public_course_prompts_exact=20,
        public_prompts_different_from_live=sum(not r['unchanged_ignoring_newlines'] for r in prompt_rows),
        public_cases=sum(len(p['test_cases']) for pid,p in new.items() if pid.startswith('public-')),
        nonempty_formulas=sum(bool(spec.get('ltl')) for p in new.values() for spec in p['specs']),
        reference_trace_results=traces['all'],provided_bounded_counts=s.load(SOURCE/'evidence/f14_bounds.json')['counts'],
        full_bounded_search_rerun=False,offline_quick_pass=True,offline_full_pass=True,
        old_data_version='v1.3-review-r8',old_data_replaced=False,old_judge_replaced=False,
        active_for_paid_experiments=False,model_calls=0,budget_events=len(ledger['events']),accounted_cny=ledger['spent_cny'],
        original_evidence_preserved=protected,new_test_schema_fields=dict(new_fields),
        interface_changes=[r['pid'] for r in rows if r['interface_changed']],
        field_change_counts={k:sum(k in r['changed_fields'] for r in rows) for k in ('requirements','variables','specs','test_cases')},
        historical_candidate_controls=controls['archived_candidates'],rows=rows,public_prompt_hashes=prompt_rows,
        native_spotchecks=native,tool_sha256=s.sha(__file__))

if __name__=='__main__':
    result=inspect()
    if sys.argv[1:]==['--check']:
        assert s.load(OUT/'review_summary.json')==result
        for name,digest in s.load(OUT/'delivery_manifest.json').get('files',{}).items():assert s.sha(OUT/name)==digest
        print('PASS F1.4 review, original public text, offline scores, native spotchecks and unchanged ledger')
    elif not sys.argv[1:]:
        OUT.mkdir(parents=True,exist_ok=True);s.atomic_json(OUT/'review_summary.json',result)
        print(json.dumps({k:result[k] for k in ('version','manifest_files_verified','reference_functional_passed','public_course_prompts_exact','public_prompts_different_from_live','interface_changes','budget_events','accounted_cny','model_calls')},ensure_ascii=False))
    else:raise SystemExit('Usage: review_f14_handoff.py [--check]')

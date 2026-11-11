"""Compare ZIP source data with the frozen live data; never execute imported project code."""
from collections import Counter
import difflib
import hashlib
import json
from pathlib import Path
import re
import sys
import zipfile
sys.path.insert(0,str(Path(__file__).resolve().parent))
import full_r8b_study as s

ARCHIVE=s.REPO/'11.10意见/STBench_F1.3_全库复核_最终工程.zip'
OUT=s.REPO/'progress/evidence/full_r8b_public_source_comparison_20261111'

def signature(problem):
    return [[v['name'],v['data_type'],v['direction']] for v in problem['variables']]

def formulas(problem):
    return Counter(re.sub(r'\s+','',p.get('ltl','')) for p in problem['specs'])

def normalized_cases(problem):
    """Ignore case labels and group labels, preserving group identity, order and test payloads.

    This is a structural comparison, not a proof of equivalence between two execution engines.
    """
    groups={};result=[]
    for case in problem['test_cases']:
        mode=case.get('mode') or problem.get('case_mode') or 'single'
        if mode.startswith('sequence'):
            name=mode.partition(':')[2] or case.get('group','')
            if name not in groups:groups[name]=len(groups)
            group=groups[name];kind='sequence'
        else:kind=mode;group=None
        result.append(dict(inputs=case.get('inputs',{}),expected=case.get('expected',{}),
            const_inputs=case.get('const_inputs',{}),init=case.get('init',{}),
            mode=kind,group=group,cycles=case.get('cycles',1),expect_full=case.get('expect_full',False)))
    return result

def compare():
    before=ARCHIVE.read_bytes();cfg=s.config();root=Path(cfg['campaign_root']);s.verify(root)
    ledger_before=Path(cfg['budget_ledger_path']).read_bytes()
    with zipfile.ZipFile(ARCHIVE) as archive:
        upstream={Path(n).stem:json.loads(archive.read(n).decode('utf-8-sig')) for n in archive.namelist()
            if n.startswith(('STBench_F1.3/datasets/public/','STBench_F1.3/datasets/selfmade/')) and n.endswith('.json')}
        actual=s.data();assert set(upstream)==set(actual)
        rows=[]
        for pid in sorted(p for p in upstream if p.startswith('public-')):
            old=upstream[pid];new=actual[pid].to_dict()
            path=s.REPO/'progress/v13_r8/datasets/public'/(pid+'.json');working=s.load(path)
            assert working['variables']==new['variables'] and working['test_cases']==new['test_cases']
            prefix='STBench_F1.3/datasets/public/'+pid+'.json';raw=archive.read(prefix)
            preserved=s.REPO/'progress/v13_r6/upstream/datasets/public'/(pid+'.json')
            assert preserved.read_bytes()==raw,'Preserved source differs from incoming archive'
            rows.append(dict(pid=pid,title=new['title'],original_sha256=hashlib.sha256(raw).hexdigest(),
                working_json_sha256=s.sha(path),same_title=old['title']==new['title'],
                changed_fields=[k for k in ('requirements','variables','test_cases','specs') if old.get(k)!=new.get(k)],
                interface_changed=signature(old)!=signature(new),old_interface=signature(old),current_interface=signature(new),
                original_cases=len(old['test_cases']),current_cases=len(new['test_cases']),
                normalized_case_payloads_equal=normalized_cases(old)==normalized_cases(new),
                original_specs=len(old['specs']),current_specs=len(new['specs']),
                formula_text_multiset_equal=formulas(old)==formulas(new),
                requirements_diff='\n'.join(difflib.unified_diff(old['requirements'].splitlines(),new['requirements'].splitlines(),
                    fromfile='STBench_F1.3',tofile='review-r8',n=2))))
    result=dict(archive=str(ARCHIVE.relative_to(s.REPO)),archive_sha256=hashlib.sha256(before).hexdigest(),
        actual_data_version='v1.3-review-r8',actual_judge='v1.3-judge-r7',study_plan_sha256=s.sha(root/'study_plan.json'),
        same_35_ids=True,all_20_public_titles_equal=all(r['same_title'] for r in rows),
        all_20_original_public_json_preserved_byte_identically=True,
        original_total_cases=sum(len(p['test_cases']) for p in upstream.values()),actual_total_cases=sum(len(p.test_cases) for p in actual.values()),
        original_public_cases=sum(r['original_cases'] for r in rows),actual_public_cases=sum(r['current_cases'] for r in rows),
        interface_changed=[r['pid'] for r in rows if r['interface_changed']],
        requirements_text_changed=[r['pid'] for r in rows if 'requirements' in r['changed_fields']],
        case_count_changed=[r['pid'] for r in rows if r['original_cases']!=r['current_cases']],
        normalized_cases_different=[r['pid'] for r in rows if not r['normalized_case_payloads_equal']],
        formula_text_multisets_different=[r['pid'] for r in rows if not r['formula_text_multiset_equal']],
        model_calls=0,rows=rows,tool_sha256=s.sha(__file__))
    assert before==ARCHIVE.read_bytes() and ledger_before==Path(cfg['budget_ledger_path']).read_bytes()
    return result

if __name__=='__main__':
    result=compare()
    if sys.argv[1:]==['--check']:
        assert s.load(OUT/'comparison.json')==result
        for name,digest in s.load(OUT/'delivery_manifest.json').get('files',{}).items():assert s.sha(OUT/name)==digest
        print('PASS source archive, preserved originals, live data and 20 public-task comparisons')
    elif not sys.argv[1:]:
        OUT.mkdir(parents=True,exist_ok=True);s.atomic_json(OUT/'comparison.json',result)
        print(json.dumps({k:v for k,v in result.items() if k!='rows'},ensure_ascii=False))
    else:raise SystemExit('Usage: compare_full_r8b_public_source.py [--check]')

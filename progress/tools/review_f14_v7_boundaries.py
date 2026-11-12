"""Free RETURN correction review and explicitly developer-patched temperature validation."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile
import f14_v6_core as s
BASE=s.REPO/'progress/f14_v7_boundary_review'
OUT=s.REPO/'progress/evidence/f14_v7_boundary_review_20261112'
OLD=s.REPO/'progress/evidence/f14_v6_public_pilot_20261112'
NATIVE=Path('E:/PLC_Dev/evidence/incoming_reviews/f14_v7_return_native_20261112_v2')


def command(args,timeout=120):
    p=subprocess.run([sys.executable,'-B','-X','utf8',*args],cwd=s.REPO,capture_output=True,text=True,encoding='utf-8',timeout=timeout)
    assert p.returncode==0,p.stderr[-3000:]
    return p


def stage(code,pid,mode='functional'):
    p=subprocess.run([sys.executable,'-B','-X','utf8',str(BASE/'judge_worker.py')],
        input=json.dumps(dict(source=code,pid=pid,mode=mode,seconds=30)),capture_output=True,text=True,encoding='utf-8',timeout=38)
    assert p.returncode==0,p.stderr[-3000:]
    return json.loads(p.stdout)


def main():
    assert not OUT.exists(),'Preserve the review evidence'
    OUT.mkdir(parents=True);cfg=s.config();ledger=Path(cfg['budget_ledger_path']);before=ledger.read_bytes()
    s.verify(cfg)
    original_hashes={p.relative_to(OLD).as_posix():s.sha(p) for p in (OLD/'jobs').rglob('*') if p.is_file()}
    log=command(['-m','unittest','discover','-s','progress/tests','-p','test_f14_v7_return.py','-v'])
    (OUT/'return_tests.log').write_text(log.stdout+log.stderr,encoding='utf-8')
    for view,args in [('native',[]),('legacy_original',['--legacy-original'])]:
        check=json.loads(command([str(BASE/'judge_audit_worker.py'),*args]).stdout)
        assert check['reference_cases']==946 and check['negative_controls']==35 and not check['private_rename_regressions']
        s.atomic_json(OUT/(view+'_reference_calibration.json'),check)
    for folder in ('original_return','removed_return_negative'):
        report=s.load(NATIVE/folder/'result.json')
        assert report['native_execution'] and not report['cleanup_errors']
        assert report['status']==('passed' if folder=='original_return' else 'test_failed')
        for name in ('job.json','result.json','FB.st','PLC_PRG.st','stdout.log','stderr.log'):
            target=OUT/'native_controls'/folder/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(NATIVE/folder/name,target)
    for name in ('completion.json','temperature_compile.json'):shutil.copyfile(NATIVE/name,OUT/name)
    records=[];items=[]
    for path in sorted((OLD/'jobs').glob('*/*.json')):
        if path.name.count('.')!=1:continue
        record=s.load(path);records.append(record)
        for attempt in record['attempts']:items.append((record,attempt))
    assert len(records)==24 and len(items)==78
    def replay(item):
        record,attempt=item
        row=dict(job_id=record['job_id'],idx=attempt['idx'],code_hash=attempt['code_hash'],
            original_functional_pass=attempt['functional_pass'],original_passed=attempt['tests_passed'],native_pass=attempt['native_pass'])
        if not attempt.get('code') or not attempt['native_pass']:return dict(row,not_replayed=True)
        result=stage(attempt['code'],record['pid']);r=result['result']
        return dict(row,result=result,functional_pass=bool(r['compiles'] and r['tests_passed']==record['tests_total']),tests_passed=r['tests_passed'])
    with ThreadPoolExecutor(max_workers=4) as pool:attempts=list(pool.map(replay,items))
    s.atomic_json(OUT/'v6_frozen_answer_replay.json',dict(functional_only=True,new_model_calls=0,original_scores_preserved=True,attempts=attempts))
    by_key={(a['job_id'],a['idx']):a for a in attempts};rows=[]
    for record in records:
        original=record['attempts'][record['best_attempt']];revised=by_key[(record['job_id'],original['idx'])]
        rows.append(dict(job_id=record['job_id'],condition=record['condition'],pid=record['pid'],original_selected_index=original['idx'],
            original_functional=original['functional_pass'],original_passed=original['tests_passed'],total=record['tests_total'],
            fixed_judge_functional=revised.get('functional_pass',False),fixed_judge_passed=revised.get('tests_passed',original['tests_passed'])))
    s.atomic_json(OUT/'preserved_selection_summary.json',dict(diagnostic_only=True,original_candidate_selection_unchanged=True,rows=rows))
    targets={}
    for pid,name in [('public-medium-03','public-medium-03.original.st'),('public-medium-04','public-medium-04.developer_fix.st')]:
        source=BASE/'developer_candidates'/name;code=source.read_text(encoding='utf-8')
        functional=stage(code,pid);bounded=stage(code,pid,'bounded')
        targets[pid]=dict(candidate_source_sha256=s.sha(source),developer_modified=pid=='public-medium-04',functional=functional,bounded=bounded)
    assert targets['public-medium-03']['functional']['result']['tests_passed']==21
    assert targets['public-medium-04']['functional']['result']['tests_passed']==37
    s.atomic_json(OUT/'two_task_validation.json',targets)
    native=s.load(NATIVE/'temperature_compile.json');assert native['status']=='passed'
    assert native['source_sha256']==targets['public-medium-04']['candidate_source_sha256']
    for rel,digest in original_hashes.items():assert s.sha(OLD/rel)==digest
    assert ledger.read_bytes()==before
    changes=[p.relative_to(BASE/'release').as_posix() for p in (BASE/'release').rglob('*') if p.is_file() and s.sha(p)!=s.sha(s.RELEASE/p.relative_to(BASE/'release'))]
    assert changes==['stbench/st/interp.py'],changes
    for pid in ('public-medium-03','public-medium-04'):
        old=BASE/'developer_candidates'/(pid+'.original.st')
        record=next(r for r in records if r['condition']=='custom_deepseek-v4pro' and r['pid']==pid)
        assert hashlib.sha256(old.read_bytes()).hexdigest()==record['attempts'][record['best_attempt']]['code_hash']
    manifest=dict(passed=True,new_model_calls=0,ledger_unchanged=True,ledger_sha256=s.sha(ledger),accounted_cny=s.load(ledger)['spent_cny'],
        original_jobs_unchanged=True,original_job_file_hashes=original_hashes,original_scores_preserved=True,
        same_judge_frozen_attempts_reviewed=78,reference_cases=946,private_rename_cases=946,negative_controls=35,
        modified_release_files=changes,average_original_code_passed=21,temperature_developer_fix_passed=37,
        temperature_fix_is_not_a_new_agent_answer=True,
        sources={p.relative_to(s.REPO).as_posix():s.sha(p) for p in [*BASE.glob('*.py'),Path(__file__),s.REPO/'progress/tests/test_f14_v7_return.py']})
    s.atomic_json(OUT/'review_audit.json',manifest)
    print('PASS free V7 review: original average 21/21, developer temperature fix 37/37; 78 responses reviewed; fees unchanged',flush=True)


if __name__=='__main__':main()

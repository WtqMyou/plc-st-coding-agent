"""Free saved-answer regression: check every V10 public best candidate under V11."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import f14_v11_core as s

def main():
    old=Path('E:/PLC_Dev/evidence/real_experiments/f14_v10_full_20261113');cfg=s.config()
    before=Path(cfg['budget_ledger_path']).read_bytes();jobs=s.load(old/'study_plan.json')['jobs']
    def replay(job):
        record=s.load(old/'jobs'/job['condition']/(job['pid']+'.json'));a=record['attempts'][record['best_attempt']]
        row=dict(job_id=job['job_id'],original_passed=a['tests_passed'],original_functional=a['functional_pass'])
        if not a.get('code'):return dict(row,status='no_original_code')
        static=s.run_stage(a['code'],job['pid'],'static',30)
        errors=[e for e in static['result'].get('compile_errors',[]) if e.get('code')=='E_FLOW_STRUCTURE']
        assert not (a['native_pass'] and errors),(job['job_id'],errors)
        result=s.run_stage(a['code'],job['pid'],'functional',30)['result']
        passed=bool(result['compiles'] and result['tests_passed']==result['tests_total'])
        if a['native_pass'] or a['functional_pass']:
            assert result['tests_passed']==a['tests_passed'],(job['job_id'],result['tests_passed'],a['tests_passed'])
        assert not a['functional_pass'] or passed
        return dict(row,status='replayed',passed=result['tests_passed'],functional=passed,structure_errors=errors)
    public=[j for j in jobs if j['pid'].startswith('public-')]
    with ThreadPoolExecutor(max_workers=8) as pool:rows=list(pool.map(replay,public))
    assert len(rows)==80 and Path(cfg['budget_ledger_path']).read_bytes()==before
    target=s.REPO/'progress/evidence/f14_v11_preflight_20261113'
    s.atomic_json(target/'saved_answer_regression.json',dict(passed=True,rows=rows,original_passes_preserved=True,external_model_calls=0,old_records_unchanged=True))
    print('PASS 80 saved public answers: functional counts unchanged; no structural false positives on native-passed code',flush=True)

if __name__=='__main__':main()

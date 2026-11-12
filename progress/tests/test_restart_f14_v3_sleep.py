"""Sleep closure is a lifecycle overlay, never a replacement answer or API retry."""
import copy
import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import restart_f14_v3_sleep_20261112 as r

class SleepRestartTests(unittest.TestCase):
    def test_all_seven_effective_records_preserve_attempts_and_raw_bytes(self):
        root=Path(r.s.config()['campaign_root']);count=0
        for p in (root/'jobs').glob('*/*.json'):
            if p.name.count('.')!=1:continue
            raw=r.RAW_LOAD(p)
            if raw['job_done']:continue
            before=p.read_bytes();closure=dict(job_id=raw['job_id'],original_record_sha256=r.s.sha(p))
            effective=r.effective_record(raw,closure)
            self.assertTrue(effective['job_done']);self.assertTrue(effective['operational_interruption'])
            self.assertEqual(effective['attempts'],raw['attempts']);self.assertEqual(effective['best_attempt'],raw['best_attempt'])
            self.assertFalse(raw['job_done']);self.assertEqual(p.read_bytes(),before);count+=1
        self.assertEqual(count,7)
    def test_closure_cannot_be_applied_to_another_job_or_completed_job(self):
        closure=dict(job_id='a/x',original_record_sha256='hash')
        with self.assertRaises(AssertionError):r.effective_record(dict(job_id='a/y',job_done=False),closure)
        with self.assertRaises(AssertionError):r.effective_record(dict(job_id='a/x',job_done=True),closure)
    def test_unknown_requests_all_have_matching_partial_records(self):
        cfg=r.s.config();ledger=r.RAW_LOAD(cfg['budget_ledger_path']);root=Path(cfg['campaign_root'])
        unknown=[e for e in ledger['events'][r.s.HISTORY:] if e['status']=='reserved']
        self.assertEqual(len(unknown),6)
        for e in unknown:
            req=e['request'];condition,pid=req['job_id'].split('/')
            record=r.RAW_LOAD(root/'jobs'/condition/(pid+'.json'))
            self.assertFalse(record['job_done']);attempt=record['attempts'][req['candidate_index']]
            self.assertTrue(attempt['provider_error']);self.assertFalse(attempt['code'])
    def test_remaining_128_have_no_existing_request_files_and_fit_210(self):
        cfg=r.s.config();root=Path(cfg['campaign_root']);plan=r.RAW_LOAD(root/'study_plan.json');remaining=[]
        for job in plan['jobs']:
            folder=root/'jobs'/job['condition']
            if r.RAW_LOAD(folder/(job['pid']+'.json')):continue
            self.assertEqual(list(folder.glob(job['pid']+'.*')),[]);remaining.append(job)
        self.assertEqual(len(remaining),128)
        bound=sum((r.s.money(j['first_upper_cny'])+r.s.money(j['repair_upper_cny']) for j in remaining),r.s.money(0))
        self.assertLessEqual(r.s.money(r.SPENT)+bound,r.s.money(210))
    def test_frozen_generation_and_judge_are_unchanged(self):r.RAW_VERIFY(r.s.config())

if __name__=='__main__':unittest.main()

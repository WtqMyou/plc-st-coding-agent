"""Read-only operational recovery checks against completed real records."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import restart_full_r8b as r
class Restart(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg=r.s.config();cls.root=Path(cls.cfg['campaign_root'])
        cls.plan=r.s.load(cls.root/'study_plan.json');cls.ledger=r.s.load(cls.cfg['budget_ledger_path'])
    def test_real_settled_boundary(self):
        result=r.audit_records(self.root,self.plan,self.ledger)
        self.assertEqual(result['completed_jobs'],44);self.assertEqual(result['settled_requests'],67)
        self.assertEqual(result['remaining_jobs'],96);self.assertEqual(result['total_accounted_cny'],46.999003)
        self.assertEqual(result['next_job'],'custom_minimax-m27/public-hard-06')
    def test_unsettled_charge_blocks_restart(self):
        ledger=copy.deepcopy(self.ledger);ledger['events'][-1]['status']='reserved'
        with self.assertRaises(AssertionError):r.audit_records(self.root,self.plan,ledger)
    def test_wrong_charge_blocks_restart(self):
        ledger=copy.deepcopy(self.ledger);ledger['events'][-1]['accounted_cny']+=.01
        with self.assertRaises(AssertionError):r.audit_records(self.root,self.plan,ledger)
    def test_duplicate_candidate_charge_blocks_restart(self):
        ledger=copy.deepcopy(self.ledger);ledger['events'].append(copy.deepcopy(ledger['events'][-1]))
        with self.assertRaises(AssertionError):r.audit_records(self.root,self.plan,ledger)
    def test_partial_record_blocks_restart(self):
        original=r.s.load;target=self.root/'jobs/custom_deepseek-v4pro/public-easy-01.json'
        def changed(path):
            record=original(path)
            if Path(path)==target:record['job_done']=False
            return record
        with patch.object(r.s,'load',side_effect=changed):
            with self.assertRaises(AssertionError):r.audit_records(self.root,self.plan,self.ledger)
    def test_prior_history_change_blocks_restart(self):
        ledger=copy.deepcopy(self.ledger);ledger['events'][0]['request_id']='changed'
        with self.assertRaises(AssertionError):r.audit_records(self.root,self.plan,ledger)
    def test_review_gate_stays_at_eighty(self):
        budget=r.s.StudyBudget(self.cfg['budget_ledger_path'],r.s.sha(self.root/'study_plan.json'),80)
        self.assertEqual(budget.review,80);self.assertEqual(budget.ceiling(),170)
        budget.admit_job(.1)
        with self.assertRaises(r.s.ReviewPause):budget.admit_job(80)
    def test_investigation_never_mutates_ledger(self):
        path=Path(self.cfg['budget_ledger_path']);before=path.read_bytes()
        r.audit_records(self.root,self.plan,self.ledger)
        self.assertEqual(before,path.read_bytes())

if __name__=='__main__':unittest.main()

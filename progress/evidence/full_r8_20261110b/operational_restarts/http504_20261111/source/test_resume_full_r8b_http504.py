"""No model calls or canonical writes: exact approved HTTP504 recovery boundary."""
import copy
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import resume_full_r8b_http504 as r
class Resume504(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg=r.s.config();cls.root=Path(cls.cfg['campaign_root'])
        cls.plan=r.s.load(cls.root/'study_plan.json');cls.ledger=r.s.load(cls.cfg['budget_ledger_path'])
    def test_actual_boundary(self):
        result=r.audit_records(self.root,self.plan,self.ledger)
        self.assertEqual(result['completed_jobs'],102);self.assertEqual(result['attempted_jobs'],103)
        self.assertEqual(result['settled_requests'],151);self.assertEqual(result['unknown_requests'],1)
        self.assertEqual(result['actual_requests'],152);self.assertEqual(result['total_accounted_cny'],55.745711)
    def test_another_unknown_request_is_not_authorized(self):
        ledger=copy.deepcopy(self.ledger);ledger['events'][-2]['status']='reserved'
        with self.assertRaises(AssertionError):r.audit_records(self.root,self.plan,ledger)
    def test_different_failure_cannot_be_masked(self):
        ledger=copy.deepcopy(self.ledger);ledger['events'][-1]['request_id']='unreviewed'
        with self.assertRaises(AssertionError):r.audit_records(self.root,self.plan,ledger)
    def test_reserve_cannot_be_refunded(self):
        ledger=copy.deepcopy(self.ledger);ledger['events'][-1]['reserved_cny']=0
        with self.assertRaises(AssertionError):r.audit_records(self.root,self.plan,ledger)
    def test_known_charge_tampering_is_rejected(self):
        ledger=copy.deepcopy(self.ledger);ledger['events'][-2]['accounted_cny']+=.01
        with self.assertRaises(AssertionError):r.audit_records(self.root,self.plan,ledger)
    def test_other_partial_job_is_rejected(self):
        original=r.s.load;target=self.root/'jobs/custom_deepseek-v4pro/public-easy-01.json'
        def changed(path):
            value=original(path)
            if Path(path)==target:value['job_done']=False
            return value
        with patch.object(r.s,'load',side_effect=changed):
            with self.assertRaises(AssertionError):r.audit_records(self.root,self.plan,self.ledger)
    def test_old_history_must_not_change(self):
        ledger=copy.deepcopy(self.ledger);ledger['events'][0]['request_id']='changed'
        with self.assertRaises(AssertionError):r.audit_records(self.root,self.plan,ledger)
    def test_audit_writes_no_cost_or_request(self):
        path=Path(self.cfg['budget_ledger_path']);before=path.read_bytes()
        r.audit_records(self.root,self.plan,self.ledger);self.assertEqual(before,path.read_bytes())
    def test_retained_reserve_counts_towards_eighty(self):
        ledger=copy.deepcopy(self.ledger);ledger['halted']=''
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'ledger.json';r.s.atomic_json(path,ledger)
            budget=r.s.StudyBudget(path,r.s.sha(self.root/'study_plan.json'),80)
            self.assertEqual(budget.review,80)
            with self.assertRaises(r.s.ReviewPause):budget.admit_job(25)
            budget.admit_job(.1)

if __name__=='__main__':unittest.main()

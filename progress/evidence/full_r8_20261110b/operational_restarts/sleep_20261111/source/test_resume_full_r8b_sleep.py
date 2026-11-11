"""Read-only boundary checks and isolated authorization fixture; no model calls."""
import copy
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import resume_full_r8b_sleep_20261111 as r

class ResumeSleep(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg=r.s.config();cls.root=Path(cls.cfg['campaign_root'])
        cls.plan=r.s.load(cls.root/'study_plan.json');cls.ledger=r.s.load(cls.cfg['budget_ledger_path'])

    def test_worker_log_encodings_are_preserved(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'worker.log'
            for encoding in ('utf-8','gbk'):
                path.write_bytes('桌面：请求超时'.encode(encoding))
                self.assertEqual(r.read_log(path),'桌面：请求超时')

    def test_actual_boundary(self):
        result=r.audit(self.cfg)
        self.assertEqual(result['completed_jobs'],117);self.assertEqual(result['attempted_jobs'],118)
        self.assertEqual(result['settled_requests'],169);self.assertEqual(result['unknown_requests'],3)
        self.assertEqual(result['actual_requests'],172);self.assertEqual(result['total_accounted_cny'],58.192297)
        self.assertEqual(result['retained_unknown_cny'],1.241276)

    def test_fourth_unknown_is_not_authorized(self):
        ledger=copy.deepcopy(self.ledger);ledger['events'][-2]['status']='reserved'
        with self.assertRaises(AssertionError):r.audit_records(self.root,self.plan,ledger)

    def test_different_failure_is_not_authorized(self):
        ledger=copy.deepcopy(self.ledger);ledger['events'][-1]['request_id']='unreviewed'
        with self.assertRaises(AssertionError):r.audit_records(self.root,self.plan,ledger)

    def test_all_reserves_must_remain(self):
        for idx in (602,612,622):
            with self.subTest(index=idx):
                ledger=copy.deepcopy(self.ledger);ledger['events'][idx]['reserved_cny']=0
                with self.assertRaises(AssertionError):r.audit_records(self.root,self.plan,ledger)

    def test_known_fee_cannot_change(self):
        ledger=copy.deepcopy(self.ledger);ledger['events'][-2]['accounted_cny']+=.01
        with self.assertRaises(AssertionError):r.audit_records(self.root,self.plan,ledger)

    def test_unreviewed_partial_is_rejected(self):
        original=r.s.load;target=self.root/'jobs/custom_deepseek-v4pro/public-easy-01.json'
        def changed(path):
            value=original(path)
            if Path(path)==target:value['job_done']=False
            return value
        with patch.object(r.s,'load',side_effect=changed):
            with self.assertRaises(AssertionError):r.audit_records(self.root,self.plan,self.ledger)

    def test_history_must_not_change(self):
        ledger=copy.deepcopy(self.ledger);ledger['events'][0]['request_id']='changed'
        with self.assertRaises(AssertionError):r.audit_records(self.root,self.plan,ledger)

    def test_audit_does_not_write_ledger(self):
        path=Path(self.cfg['budget_ledger_path']);before=path.read_bytes()
        r.audit_records(self.root,self.plan,self.ledger)
        self.assertEqual(before,path.read_bytes())

    def test_eighty_guard_includes_all_retained_reserves(self):
        ledger=copy.deepcopy(self.ledger);ledger['halted']='';ledger.pop('halt_details',None)
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'ledger.json';r.s.atomic_json(path,ledger)
            budget=r.s.StudyBudget(path,r.s.sha(self.root/'study_plan.json'),80)
            before=path.read_bytes()
            with self.assertRaises(r.s.ReviewPause):budget.admit_job(21.9)
            self.assertEqual(before,path.read_bytes())
            budget.admit_job(.1)

    def test_authorization_changes_no_events_answers_or_fees(self):
        canonical=Path(self.cfg['budget_ledger_path']);canonical_before=canonical.read_bytes()
        source=self.root/'jobs'/ (r.retained.TARGET+'.json')
        original=source.read_bytes();original_record=r.s.load(source)
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);private=root/'operational';private.mkdir()
            ledgerpath=root/'ledger.json';ledgerpath.write_bytes(canonical_before)
            target=root/'jobs'/(r.retained.TARGET+'.json');target.parent.mkdir(parents=True)
            target.write_bytes(original)
            (root/'study_plan.json').write_bytes((self.root/'study_plan.json').read_bytes())
            cfg=dict(self.cfg,campaign_root=str(root),budget_ledger_path=str(ledgerpath))
            proof=dict(ledger_checkpoint_sha256=r.s.sha(ledgerpath),failed_record_before_sha256=r.s.sha(target))
            audit=r.retained.audit_records
            with patch.object(r.retained,'audit_records',side_effect=lambda _,p,l:audit(self.root,p,l)):
                r.retained.authorize(cfg,proof,private,r.TAG)
            after=r.s.load(ledgerpath);closed=r.s.load(target)
            self.assertEqual(after['events'],self.ledger['events'])
            self.assertEqual(after['spent_cny'],58.192297);self.assertEqual(after['limit_cny'],170)
            self.assertEqual(after['recoveries'],self.ledger['recoveries'])
            self.assertEqual(after['operational_recoveries'][:-1],self.ledger['operational_recoveries'])
            self.assertFalse(after['halted']);self.assertNotIn('halt_details',after)
            self.assertTrue(closed['job_done']);self.assertEqual(closed['attempts'],original_record['attempts'])
            self.assertEqual(closed['solved'],original_record['solved'])
            self.assertEqual(r.s.load(private/'manual_recovery.json')['next_job'],'codex_deepseek-v4pro/self-medium-01')
            checkpoint=r.s.load(root/'ledger_checkpoint.json')
            self.assertEqual(checkpoint['events'],623);self.assertEqual(checkpoint['sha256'],r.s.sha(ledgerpath))
        self.assertEqual(canonical_before,canonical.read_bytes());self.assertEqual(original,source.read_bytes())

if __name__=='__main__':unittest.main()

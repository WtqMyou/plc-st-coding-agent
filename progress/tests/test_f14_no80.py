"""No-80 authorization, capped budget and clean handoff without live ledger mutations."""
import copy
from datetime import datetime,timezone
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import f14_no80 as n
import f14_rotation_budget as b
from stbench.providers.base import ProviderError

class AmendmentTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name);self.path=self.root/'ledger.json'
        self.before=dict(version=3,limit_cny=190,spent_cny=79.5,halted='',recoveries=[dict(kept=True)],events=[],
            f14_rotation_authorization=dict(study_plan_sha256='parent',total_cap_cny=190,review_pause_cny=80,primary_switch_checkpoint_cny=75))
        n.atomic_json(self.path,self.before);self.raw=self.path.read_bytes()
        n.authorize(self.path,self.raw,'parent','amendment');self.budget=n.Budget(self.path,'parent','amendment','secondary')
        self.budget.context=dict(job_id='arm/task',candidate_index=0)
    def test_no_80_pause_for_complete_job(self):
        before=self.path.read_bytes();self.budget.admit_job(1.5);self.assertEqual(before,self.path.read_bytes())
    def test_request_above_80_allowed_within_190(self):
        self.budget.reserve(1);state=n.load(self.path)
        self.assertEqual(state['spent_cny'],80.5);self.assertEqual(state['events'][-1]['review_checkpoint_cny'],190)
        self.assertFalse(state['events'][-1]['manual_pause_at_80'])
    def test_190_total_cap_still_blocks_job(self):
        with self.assertRaises(ProviderError):self.budget.admit_job(111)
    def test_pending_reservations_still_protected(self):
        self.budget.protected_cny=110
        with self.assertRaises(ProviderError):self.budget.reserve(1)
        self.assertEqual(len(n.load(self.path)['events']),0)
    def test_primary_75_guard_preserved(self):
        self.budget.active_batch='primary'
        with self.assertRaises(b.KeySwitch):self.budget.admit_job(.1)
        with self.assertRaises(b.KeySwitch):self.budget.reserve(.1)
    def test_authorization_preserves_history_and_old_80_record(self):
        state=n.load(self.path);self.assertTrue(n.prefix_ok(state,self.before));self.assertEqual(state['spent_cny'],79.5)
        self.assertEqual(state['f14_rotation_authorization']['review_pause_cny'],80)
        self.assertFalse(state['f14_no80_authorization']['manual_pause_at_80'])
    def test_missing_new_authorization_rejected(self):
        n.atomic_json(self.path,self.before)
        with self.assertRaises(ProviderError):n.Budget(self.path,'parent','amendment','secondary')
    def test_event_links_authorization_and_no_duplicate_candidate(self):
        self.budget.reserve(.1);event=n.load(self.path)['events'][-1]
        self.assertEqual(event['request']['execution_amendment_sha256'],'amendment')
        with self.assertRaises(ProviderError):self.budget.reserve(.1)
    def test_halted_ledger_not_recovered_by_no80(self):
        value=copy.deepcopy(self.before);value['halted']='Unknown fee';n.atomic_json(self.path,value)
        with self.assertRaises(AssertionError):n.authorize(self.path,self.path.read_bytes(),'parent','new')
    def test_unsettled_new_request_blocks_activation(self):
        value=copy.deepcopy(self.before);value['events']=[dict(status='old') for _ in range(n.HISTORY)]+[dict(status='reserved')]
        n.atomic_json(self.path,value)
        with self.assertRaises(AssertionError):n.authorize(self.path,self.path.read_bytes(),'parent','new')
    def test_clean_checkpoint_waits_for_actual_process_exit(self):
        with patch.object(n,'alive',return_value=True):self.assertEqual(n.ready(dict(state='paused_for_api_review'),{}),'wait')
        with patch.object(n,'alive',return_value=False):self.assertEqual(n.ready(dict(state='paused_for_api_review'),{}),'activate')
    def test_faults_never_auto_resume(self):
        self.assertEqual(n.ready(dict(state='stopped'),{}),'fault')
        with patch.object(n,'alive',return_value=False):self.assertEqual(n.ready(dict(state='running'),{}),'fault')
    def test_finished_parent_never_requests_more(self):self.assertEqual(n.ready(dict(state='completed'),{}),'completed')
    def test_pid_reuse_does_not_identify_old_runner(self):
        fake=type('P',(),dict(is_running=lambda self:True,create_time=lambda self:100,status=lambda self:'running'))()
        with patch.object(n.psutil,'Process',return_value=fake):
            self.assertFalse(n.alive(dict(pid=1,process_created_at=datetime.fromtimestamp(0,timezone.utc).isoformat())))

if __name__=='__main__':unittest.main()

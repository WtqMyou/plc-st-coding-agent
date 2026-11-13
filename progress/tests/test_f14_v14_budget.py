"""Free concurrency, budget and judge calibration; never use the live ledger."""
from concurrent.futures import ThreadPoolExecutor
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import f14_v14_core as s
import f14_v14_budget as b
from full_r8b_transport import MeteredProvider
from stbench.providers.base import ProviderError

GOOD='FUNCTION_BLOCK FB VAR_OUTPUT x:BOOL;END_VAR x:=TRUE;END_FUNCTION_BLOCK'
BAD=GOOD.replace('TRUE','FALSE')

class BudgetTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        self.patch_h=patch.object(b,'HISTORY',3);self.patch_b=patch.object(b,'BASELINE',10)
        self.patch_h.start();self.patch_b.start();self.addCleanup(self.patch_h.stop);self.addCleanup(self.patch_b.stop)
        self.path=self.root/'ledger.json';self.before=dict(version=3,limit_cny=420,spent_cny=10,events=[dict(phase='history') for _ in range(3)],recoveries=[],historic_authorization=dict(keep=True))
        state=copy.deepcopy(self.before);state.update(limit_cny=b.TOTAL,halted='',active_experiment_scope=dict(conditions=['arm']),f14_v14_authorization=dict(study_plan_sha256='plan',total_cap_cny=b.TOTAL))
        s.atomic_json(self.path,state)
        self.jobs=[dict(job_id='arm/task'+str(i),first_upper_cny=.1,repair_upper_cny=.1) for i in range(141)]
        self.plan=dict(sha256='plan',jobs=self.jobs);self.co=b.Coordinator(self.path,self.plan,baseline=self.before)
        for bounds in self.co.bounds.values():
            for idx in bounds:bounds[idx]=s.money(.9)
        self.co.pending={k:dict(v) for k,v in self.co.bounds.items()}
        for key in list(self.co.pending)[40:]:self.co.pending[key]={i:s.money(0) for i in range(4)}
    def view(self,index,attempt=0):
        job=self.jobs[index]['job_id'];view=self.co.view(job);view.context=dict(job_id=job,candidate_index=attempt);return view
    def test_8_concurrent_reservations_and_settlements_are_exact(self):
        barrier=threading.Barrier(8)
        def run(i):
            view=self.view(i);barrier.wait();index=view.reserve(.4);time.sleep(.02);view.settle(index,.1,metadata=dict(model='mock'));self.co.finish(view.job_id)
        with ThreadPoolExecutor(max_workers=8) as pool:list(pool.map(run,range(8)))
        ledger=self.co.read();self.assertEqual(len(ledger['events']),11);self.assertEqual(ledger['spent_cny'],10.8)
        self.assertEqual(ledger['events'][:3],self.before['events'])
    def test_protected_future_costs_block_before_sending(self):
        self.co.pending['huge']={0:s.money(b.TOTAL)};before=self.path.read_bytes()
        with self.assertRaises(ProviderError):self.view(0).reserve(.4)
        self.assertEqual(before,self.path.read_bytes())
    def test_duplicate_and_fifth_candidate_rejected(self):
        view=self.view(0);view.reserve(.4)
        with self.assertRaises(ProviderError):view.reserve(.4)
        with self.assertRaises(AssertionError):self.view(1,4).reserve(.1)
    def test_halt_blocks_new_sends_but_other_inflight_receipt_settles(self):
        a=self.view(0);c=self.view(1);a.reserve(.4);index=c.reserve(.4)
        a.halt('unknown',details=dict(category='mock'))
        with self.assertRaises(b.CampaignStopped):self.view(2).reserve(.1)
        c.settle(index,.1,metadata=dict(model='mock'))
        ledger=self.co.read(allow_halted=True);self.assertEqual(ledger['events'][3]['status'],'reserved');self.assertEqual(ledger['events'][4]['status'],'settled')
        self.assertEqual(ledger['spent_cny'],10.5);self.assertEqual(ledger['halted'],'unknown')
    def test_no_shared_mutable_request_context(self):
        a,c=self.view(0),self.view(1);self.assertIsNot(a.context,c.context)
        ai=a.reserve(.4);ci=c.reserve(.3);l=self.co.read();self.assertNotEqual(l['events'][ai]['request']['job_id'],l['events'][ci]['request']['job_id'])
    def test_restored_coordinator_cannot_repeat_a_reserved_request(self):
        self.view(0).reserve(.4);restored=b.Coordinator(self.path,self.plan,baseline=self.before)
        view=restored.view(self.jobs[0]['job_id']);view.context=dict(job_id=view.job_id,candidate_index=0)
        with self.assertRaises(ProviderError):view.reserve(.4)
    def test_maximum_480_requests_blocks_the_481st_before_charging(self):
        for index in range(120):
            for attempt in range(4):self.view(index,attempt).reserve(0)
        before=self.path.read_bytes()
        with self.assertRaises(ProviderError):self.view(120).reserve(0)
        self.assertEqual(before,self.path.read_bytes())
    def test_authorization_retains_old_unknown_fee_and_is_idempotent(self):
        original=copy.deepcopy(self.before)
        original.update(halted='V13_SELF_FULL_COMPLETED_OTHER_GROUPS_PAUSED')
        original['events'][-1]=dict(request_id='historical_unknown',status='reserved',reserved_cny=.121743,phase='previous_batch')
        s.atomic_json(self.path,original);before=self.path.read_bytes()
        b.authorize(self.path,before,'plan','proof',worst_reservation_cny=0);state=s.load(self.path)
        self.assertEqual(state['events'],original['events']);self.assertEqual(state['spent_cny'],10)
        self.assertEqual(state['limit_cny'],b.TOTAL);self.assertEqual(state['events'][-1]['status'],'reserved')
        raw=self.path.read_bytes();b.authorize(self.path,before,'plan','proof',worst_reservation_cny=0);self.assertEqual(self.path.read_bytes(),raw)

    def test_underfunded_plan_does_not_change_ledger(self):
        original=copy.deepcopy(self.before);original['halted']='V13_SELF_FULL_COMPLETED_OTHER_GROUPS_PAUSED'
        s.atomic_json(self.path,original);before=self.path.read_bytes()
        with self.assertRaises(AssertionError):b.authorize(self.path,before,'plan','proof',worst_reservation_cny=b.TOTAL+1)
        self.assertEqual(self.path.read_bytes(),before)

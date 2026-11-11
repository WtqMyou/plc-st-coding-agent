"""Credential rotation and no-reissue gates over a temporary 653-event ledger."""
import copy
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import f14_rotation_study as s
import f14_rotation_budget as b
import f14_rotation_credentials as keys
import f14_study as base
from full_r8b_transport import MeteredProvider
from stbench.providers.base import ProviderError

class RotationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.path=self.root/'ledger.json'
        self.before=dict(version=3,limit_cny=170,spent_cny=b.BASELINE,halted='',recoveries=[dict(old=True)],
            full_r8b_authorization=dict(old=True),events=[dict(phase='old',status='reserved',reserved_cny=0) for _ in range(653)])
        s.atomic_json(self.path,self.before);self.raw=self.path.read_bytes()
        b.authorize(self.path,self.raw,'plan','now');self.budget=b.StudyBudget(self.path,'plan')
        self.budget.context=dict(job_id='arm/task',candidate_index=0,study_kind='ignored-legacy-kind')
    def spent(self,value):
        state=s.load(self.path);state['spent_cny']=value;s.atomic_json(self.path,state)
    def test_authorization_preserves_original_events_and_unknowns(self):
        state=s.load(self.path);self.assertTrue(b.prefix_ok(state,self.before));self.assertEqual(len(state['events']),653)
        self.assertEqual(state['spent_cny'],b.BASELINE);self.assertEqual(state['limit_cny'],190)
    def test_authorization_idempotent(self):
        raw=self.path.read_bytes();b.authorize(self.path,self.raw,'plan','later');self.assertEqual(raw,self.path.read_bytes())
    def test_switch_before_complete_job_crosses_75(self):
        self.spent(74.5);raw=self.path.read_bytes()
        with self.assertRaises(b.KeySwitch):self.budget.admit_job(.500001)
        self.assertEqual(raw,self.path.read_bytes())
    def test_exact_75_job_reservation_allowed(self):
        self.spent(74.5);self.budget.admit_job(.5);self.assertEqual(len(s.load(self.path)['events']),653)
    def test_primary_request_guard_has_no_fee_event(self):
        self.spent(74.9);raw=self.path.read_bytes()
        with self.assertRaises(b.KeySwitch):self.budget.reserve(.100001)
        self.assertEqual(raw,self.path.read_bytes())
    def test_secondary_keeps_80_job_pause(self):
        self.spent(79.5);self.budget.active_batch='secondary';raw=self.path.read_bytes()
        with self.assertRaises(b.ReviewPause):self.budget.admit_job(.500001)
        self.assertEqual(raw,self.path.read_bytes())
    def test_secondary_request_guard_keeps_80_pause(self):
        self.spent(79.99);self.budget.active_batch='secondary';raw=self.path.read_bytes()
        with self.assertRaises(b.ReviewPause):self.budget.reserve(.02)
        self.assertEqual(raw,self.path.read_bytes())
    def test_global_cap_still_protects_pending_requests(self):
        self.budget.protected_cny=130
        with self.assertRaises(ProviderError):self.budget.reserve(.1)
    def test_event_stamps_actual_credential_and_new_batch(self):
        self.budget.active_batch='secondary';self.budget.reserve(.1)
        event=s.load(self.path)['events'][-1]
        self.assertEqual(event['phase'],b.KIND);self.assertEqual(event['request']['study_kind'],b.KIND)
        self.assertEqual(event['request']['credential_batch'],'secondary')
    def test_duplicate_candidate_not_reissued_after_switch(self):
        self.budget.reserve(.1);self.budget.active_batch='secondary'
        with self.assertRaises(ProviderError):self.budget.reserve(.1)
        self.assertEqual(len(s.load(self.path)['events']),654)
    def test_unknown_fee_never_triggers_automatic_key_fallback(self):
        self.budget.reserve(.1);self.budget.halt('Synthetic unknown fee')
        with self.assertRaises(ProviderError):self.budget.admit_job(.1)
        self.assertEqual(self.budget.active_batch,'primary');self.assertEqual(s.load(self.path)['events'][-1]['status'],'reserved')
    def test_metadata_keeps_two_independent_batches(self):
        cfg=s.config();cfg['budget_ledger_path']=str(self.path);(self.root/'study_plan.json').write_text('{}')
        s.bind_batch(cfg,self.root,{},'primary',dict(authenticated=True),{'first':1})
        s.bind_batch(cfg,self.root,{},'secondary',dict(authenticated=True),{'next':1})
        self.assertEqual(s.load(self.root/'credential_batches/primary.json')['state'],'closed_before_75')
        self.assertEqual(s.load(self.root/'current_credential_batch.json')['slot'],'secondary')
        with self.assertRaises(AssertionError):s.bind_batch(cfg,self.root,{},'primary',{},{} )
    def test_factory_does_not_overwrite_primary_model_spec(self):
        spec=copy.deepcopy(s.config()['models'][0]);original=copy.deepcopy(spec);self.budget.active_batch='secondary';seen=[]
        with patch('full_r8b_transport.MeteredProvider',side_effect=lambda selected,*args,**kwargs:seen.append(selected)):
            keys.provider_factory(spec,self.budget,max_tokens=16384)
        self.assertEqual(spec,original);self.assertEqual(seen[0]['api_key_env'],keys.SECONDARY_ENV)
        for field in ('model','parameters','base_url','input_cny_per_million','output_cny_per_million'):
            self.assertEqual(seen[0][field],original[field])
    def test_read_only_catalog_accepts_only_frozen_models(self):
        data=json.dumps(dict(data=[dict(id=m['model']) for m in s.config()['models']])).encode()
        with patch.dict(os.environ,{keys.SECONDARY_ENV:'local-fixture-credential'}),patch.object(keys.urllib.request,'urlopen',return_value=io.BytesIO(data)):
            result=keys.catalog(s.config(),'secondary')
        self.assertEqual(result['generation_requests'],0);self.assertTrue(all(result['selected_models'].values()))
    def test_catalog_missing_model_stops_before_generation(self):
        with patch.dict(os.environ,{keys.SECONDARY_ENV:'local-fixture-credential'}),patch.object(keys.urllib.request,'urlopen',return_value=io.BytesIO(b'{"data":[]}')):
            with self.assertRaises(ProviderError):keys.catalog(s.config(),'secondary')
    def test_new_plan_keeps_140_tasks_and_same_prices(self):
        cfg=s.config();plan=s.build_plan(cfg,s.load(cfg['budget_ledger_path']))
        self.assertEqual(len(plan['jobs']),140);self.assertEqual(plan['kind'],b.KIND)
        self.assertEqual(plan['worst_reservation_cny'],119.784853);self.assertEqual(cfg['models'],base.config()['models'])
    def test_rotation_then_full_job_uses_only_secondary(self):
        self.spent(74.5);cfg=copy.deepcopy(s.config());cfg['budget_ledger_path']=str(self.path)
        (self.root/'study_plan.json').write_text('{}')
        job=dict(pid='public-easy-01',framework='custom',model_id='deepseek-v4pro',condition='custom_deepseek-v4pro',
            job_id='custom_deepseek-v4pro/public-easy-01',first_upper_cny=1,repair_upper_cny=1)
        job['initial_user_sha256']=s.hashlib.sha256(base.messages(job)[1]['content'].encode()).hexdigest()
        with self.assertRaises(b.KeySwitch):self.budget.admit_job(2)
        self.budget.active_batch='secondary';self.budget.admit_job(2)
        def factory(spec,budget,**kwargs):
            def sender(*args):
                return dict(model=spec['model'],status='completed',usage=dict(input_tokens=0,output_tokens=0),
                    output=[dict(type='message',content=[dict(type='output_text',text='FUNCTION_BLOCK FB END_FUNCTION_BLOCK')])])
            return MeteredProvider(spec,budget,**kwargs,offline=True,sender=sender)
        def evaluate(*args):
            return dict(result=dict(compiles=True,tests_total=10,tests_passed=10,compile_errors=[],platform_results=dict(codesys=dict(status='passed'))),
                complete_code=True,verification_status='truncated',feedback='Local fixture',shared_tool_error=False)
        record=base.generate_job(cfg,self.root,{},job,self.budget,{job['job_id']:2},factory=factory,evaluator=evaluate)
        self.assertTrue(record['job_done']);self.assertEqual(len(s.load(self.path)['events']),654)
        self.assertEqual(s.load(self.path)['events'][-1]['request']['credential_batch'],'secondary')

if __name__=='__main__':unittest.main()

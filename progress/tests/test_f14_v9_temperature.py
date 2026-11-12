"""Single-task repair inputs, budget protection and real metered transport against local responses."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import f14_v9_temperature_core as s
import f14_v9_temperature_budget as b
GOOD='FUNCTION_BLOCK FB VAR_OUTPUT x:BOOL;END_VAR x:=TRUE;END_FUNCTION_BLOCK'


class AutonomousRepairTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        for name,value in [('HISTORY',3),('BASELINE',10)]:
            active=patch.object(b,name,value);active.start();self.addCleanup(active.stop)
        self.path=self.root/'ledger.json'
        self.before=dict(version=3,limit_cny=210,spent_cny=10,events=[dict(phase='history') for _ in range(3)],recoveries=[],historic_authorization=dict(keep=True))
        current=copy.deepcopy(self.before);current.update(halted='',f14_v9_temperature_authorization=dict(study_plan_sha256='fixture',total_cap_cny=210))
        s.atomic_json(self.path,current)
        condition='custom_deepseek-v4pro';pid=s.PID
        self.job=dict(pid=pid,framework='custom',model_id='deepseek-v4pro',condition=condition,job_id=condition+'/'+pid,first_upper_cny=1,repair_upper_cny=1,
            initial_user_sha256=hashlib.sha256(s.messages(dict(pid=pid))[1]['content'].encode()).hexdigest())
        self.co=b.Coordinator(self.path,dict(sha256='fixture',jobs=[self.job]),baseline=self.before)
        (self.root/'study_plan.json').write_text('{}')
    def view(self,idx):
        view=self.co.view(self.job['job_id']);view.context=dict(job_id=self.job['job_id'],candidate_index=idx);return view
    def test_prompt_contains_original_model_seed_and_no_answer_or_expected_values(self):
        messages=s.messages(self.job);metadata=s.load(s.PACK/'seed_metadata.json')
        self.assertEqual(hashlib.sha256(messages[2]['content'].encode()).hexdigest(),metadata['original_candidate_sha256'])
        self.assertEqual(hashlib.sha256(messages[1]['content'].encode()).hexdigest(),metadata['original_user_sha256'])
        self.assertFalse(metadata['developer_patch_used'])
        text=json.dumps(messages,ensure_ascii=False)
        for forbidden in ('"expected":','"note":','PT := T#5001MS','.developer_fix.st','__spec_'):self.assertNotIn(forbidden,text)
        self.assertIn('first_satisfying_tick_ms',text)
        self.assertIn('require strict >',text)
    def test_duplicate_and_third_candidate_block_before_charging(self):
        view=self.view(0);view.reserve(.5)
        with self.assertRaises(s.ProviderError):view.reserve(.5)
        before=self.path.read_bytes()
        with self.assertRaises(AssertionError):self.view(2).reserve(.5)
        self.assertEqual(before,self.path.read_bytes())
    def test_future_reservations_protect_the_total_cap(self):
        self.co.pending['other']={0:s.money(209)};before=self.path.read_bytes()
        with self.assertRaises(s.ProviderError):self.view(0).reserve(.5)
        self.assertEqual(before,self.path.read_bytes())
    def test_halt_retains_inflight_reservation_and_blocks_another_send(self):
        self.view(0).reserve(.5);self.co.halt('unknown result')
        with self.assertRaises(b.CampaignStopped):self.view(1).reserve(.5)
        state=self.co.read(allow_halted=True);self.assertEqual(state['events'][-1]['status'],'reserved')
        self.assertEqual(state['spent_cny'],10.5)
    def factory(self,kind='success'):
        def build(spec,budget,**kwargs):
            def sender(*args):
                return dict(model='wrong-model' if kind=='identity' else spec['model'],status='incomplete' if kind=='empty' else 'completed',
                    usage=dict(input_tokens=1,output_tokens=1),output=[] if kind=='empty' else [dict(type='message',content=[dict(type='output_text',text=GOOD)])])
            return s.MeteredProvider(spec,budget,**kwargs,offline=True,sender=sender)
        return build
    def evaluator(self,passed):
        return lambda *args:dict(result=dict(compiles=True,compile_errors=[],tests_total=37,tests_passed=37 if passed else 35,
            platform_results=dict(codesys=dict(status='passed'))),verification_status='inconclusive' if passed else 'not_run',
            feedback='Observed execution; review the original public contract.',complete_code=True,shared_tool_error=False)
    def run_job(self,kind='success',passed=True):
        return s.generate_job(s.config(),self.root,{},self.job,self.co.view(self.job['job_id']),{},factory=self.factory(kind),evaluator=self.evaluator(passed))
    def test_success_stops_after_one_real_transport_fixture_request(self):
        result=self.run_job();self.assertTrue(result['job_done']);self.assertEqual(len(result['attempts']),1)
        state=self.co.read();self.assertEqual(len(state['events'])-3,1);self.assertEqual(state['events'][-1]['status'],'settled')
    def test_empty_response_does_not_trigger_automatic_resend(self):
        result=self.run_job('empty');self.assertTrue(result['job_done']);self.assertEqual(result['stop_reason'],'generation_incomplete')
        self.assertEqual(len(self.co.read()['events'])-3,1)
    def test_wrong_identity_halts_and_preserves_the_reservation(self):
        with self.assertRaises(s.ProviderError):self.run_job('identity')
        state=self.co.read(allow_halted=True);self.assertEqual(len(state['events'])-3,1)
        self.assertTrue(state['halted']);self.assertEqual(state['events'][-1]['status'],'reserved')
    def test_repeated_candidate_stops_without_third_request(self):
        result=self.run_job(passed=False)
        self.assertEqual(result['stop_reason'],'repeated_candidate');self.assertEqual(len(result['attempts']),2)
        self.assertEqual(len(self.co.read()['events'])-3,2)


class PublicTimeArithmetic(unittest.TestCase):
    def derive(self,text,quantum=1):
        import importlib.util
        spec=importlib.util.spec_from_file_location('isolated_public_time_bounds',s.PACK/'public_time_bounds.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        return module.derive(text,quantum)
    def test_strict_whole_period_uses_next_representable_tick(self):
        row=self.derive('The heater runs for more than a period (using 5s).')[0]
        self.assertEqual(row['comparison'],'>');self.assertEqual(row['first_satisfying_tick_ms'],5001)
    def test_nonstrict_period_keeps_equal_tick(self):
        self.assertEqual(self.derive('Wait at least 5 seconds.')[0]['first_satisfying_tick_ms'],5000)
    def test_decimal_resolution_is_derived_without_float_rounding(self):
        self.assertEqual(self.derive('Signal exceeds 0.0015 seconds.')[0]['first_satisfying_tick_ms'],2)
    def test_arbitrary_quantum_and_no_timed_requirement(self):
        self.assertEqual(self.derive('Signal exceeds 100 ms.',10)[0]['first_satisfying_tick_ms'],110)
        self.assertEqual(self.derive('Copy the Boolean input.'),[])

if __name__=='__main__':unittest.main()

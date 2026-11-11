"""New-study gates and real local-only controller paths; never touch the live ledger."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import f14_study as s
import f14_study_budget as b
from full_r8b_transport import MeteredProvider
from stbench.providers.base import ProviderError

BAD='FUNCTION_BLOCK FB VAR_OUTPUT x:BOOL; END_VAR x:=FALSE; END_FUNCTION_BLOCK'
GOOD=BAD.replace('FALSE','TRUE')

def baseline():
    value=dict(version=3,limit_cny=170,spent_cny=b.BASELINE,halted='',recoveries=[dict(retained=True)],
        full_r8b_authorization=dict(original=True),events=[dict(phase='historic',status='settled',reserved_cny=0) for _ in range(b.HISTORY)])
    value['events'][-1]=dict(phase='historic',status='reserved',reserved_cny=.5)
    return value

def evaluation(passed=True,status='truncated',native='passed'):
    return dict(result=dict(compiles=True,compile_errors=[],tests_total=10,tests_passed=10 if passed else 0,
        cases=[],model_check=dict(executed=status!='not_run',violations=[]),
        platform_results=dict(codesys=dict(status=native)),evidence_metadata={}),complete_code=True,
        verification_status=status,feedback='Compilation/function/formal feedback without hidden values.',shared_tool_error=False)

class BudgetTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.path=self.root/'ledger.json';self.before=baseline()
        s.atomic_json(self.path,self.before);self.before_bytes=self.path.read_bytes()
        b.authorize(self.path,self.before_bytes,'plan','now');self.budget=b.StudyBudget(self.path,'plan')
        self.budget.context=dict(job_id='arm/task',candidate_index=0)
    def test_authorization_preserves_all_history_and_reserves(self):
        state=s.load(self.path);self.assertEqual(state['limit_cny'],190);self.assertEqual(state['spent_cny'],b.BASELINE)
        self.assertTrue(b.prefix_ok(state,self.before));self.assertEqual(len(state['events']),653)
    def test_authorization_idempotent(self):
        before=self.path.read_bytes();b.authorize(self.path,self.before_bytes,'plan','later');self.assertEqual(before,self.path.read_bytes())
    def test_changed_baseline_rejected(self):
        other=self.root/'other.json';s.atomic_json(other,self.before);raw=other.read_bytes()
        changed=copy.deepcopy(self.before);changed['spent_cny']+=1;s.atomic_json(other,changed)
        with self.assertRaises(ProviderError):b.authorize(other,raw,'plan','now')
    def test_job_pause_before_request_has_no_fee_event(self):
        state=s.load(self.path);state['spent_cny']=79.9;s.atomic_json(self.path,state);before=self.path.read_bytes()
        with self.assertRaises(b.ReviewPause):self.budget.admit_job(.2)
        self.assertEqual(before,self.path.read_bytes())
    def test_request_pause_has_no_fee_event(self):
        state=s.load(self.path);state['spent_cny']=79.99;s.atomic_json(self.path,state);before=self.path.read_bytes()
        with self.assertRaises(b.ReviewPause):self.budget.reserve(.02)
        self.assertEqual(before,self.path.read_bytes())
    def test_global_protection_keeps_future_reservations(self):
        self.budget.protected_cny=130
        with self.assertRaises(ProviderError):self.budget.reserve(.1)
        self.assertEqual(len(s.load(self.path)['events']),653)
    def test_duplicate_candidate_cannot_reserve_twice(self):
        self.budget.reserve(.1)
        with self.assertRaises(ProviderError):self.budget.reserve(.1)
        self.assertEqual(len(s.load(self.path)['events']),654)
    def test_third_candidate_rejected(self):
        self.budget.context['candidate_index']=2
        with self.assertRaises(ProviderError):self.budget.reserve(.1)
    def test_280_maximum_requests(self):
        state=s.load(self.path);state['events'] += [dict(phase=b.KIND,request=dict(job_id='x/'+str(i),candidate_index=0)) for i in range(280)]
        s.atomic_json(self.path,state)
        with self.assertRaises(ProviderError):self.budget.reserve(.1)
    def test_halted_ledger_not_automatically_recovered(self):
        self.budget.halt('Synthetic unknown fee')
        with self.assertRaises(ProviderError):self.budget.reserve(.1)
    def test_unknown_reserve_survives(self):
        self.budget.reserve(.1);self.budget.halt('Synthetic unknown fee')
        state=s.load(self.path);self.assertEqual(state['events'][-1]['status'],'reserved')
        self.assertEqual(s.money(state['spent_cny']),s.money(b.BASELINE)+s.money(.1))

class ControllerTests(unittest.TestCase):
    def setUp(self):
        BudgetTests.setUp(self);self.cfg=copy.deepcopy(s.config());self.cfg['budget_ledger_path']=str(self.path)
        (self.root/'study_plan.json').write_text('{}',encoding='utf-8')
        self.job=dict(pid='public-easy-01',framework='custom',model_id='deepseek-v4pro',condition='custom_deepseek-v4pro',
            job_id='custom_deepseek-v4pro/public-easy-01',first_upper_cny=2,repair_upper_cny=2)
        self.job['initial_user_sha256']=s.hashlib.sha256(s.messages(self.job)[1]['content'].encode()).hexdigest()
        self.pending={self.job['job_id']:4};self.sent=[]
    def factory(self,codes,*,incomplete=False,error=None,identity=None):
        def create(spec,budget,**kwargs):
            def sender(url,payload,key,timeout):
                self.sent.append(payload)
                if error:raise error
                code=codes[min(len(self.sent)-1,len(codes)-1)]
                return dict(model=identity or spec['model'],status='incomplete' if incomplete else 'completed',
                    usage=dict(input_tokens=0,output_tokens=0),output=[dict(type='message',content=[dict(type='output_text',text=code)])])
            return MeteredProvider(spec,budget,**kwargs,offline=True,sender=sender)
        return create
    def run_job(self,codes,evaluator=None,**kwargs):
        return s.generate_job(self.cfg,self.root,{},self.job,self.budget,self.pending,
            factory=self.factory(codes,**kwargs),evaluator=evaluator or (lambda *args:evaluation()))
    def test_pass_and_truncated_formal_stops_after_one(self):
        r=self.run_job([GOOD]);self.assertEqual(len(self.sent),1);self.assertTrue(r['job_done']);self.assertEqual(len(r['attempts']),1)
    def test_one_repair_contains_previous_code_and_feedback(self):
        r=self.run_job([BAD,GOOD],lambda source,*args:evaluation(source==GOOD))
        self.assertEqual(len(self.sent),2);self.assertEqual(r['best_attempt'],1)
        content=json.dumps(self.sent[-1]['input']);self.assertIn(BAD,content);self.assertIn('without hidden values',content)
    def test_repeated_candidate_stops_after_two(self):
        r=self.run_job([BAD,BAD],lambda *args:evaluation(False));self.assertEqual(r['stop_reason'],'repeated_candidate');self.assertEqual(len(self.sent),2)
    def test_incomplete_response_is_not_retried(self):
        r=self.run_job([BAD],incomplete=True);self.assertTrue(r['job_done']);self.assertEqual(len(self.sent),1)
        self.assertEqual(r['stop_reason'],'generation_incomplete');self.assertEqual(s.load(self.path)['events'][-1]['status'],'settled')
    def test_unknown_fee_stops_and_preserves_reservation(self):
        with self.assertRaises(ProviderError):self.run_job([BAD],error=ProviderError('Synthetic EOF'))
        self.assertEqual(len(self.sent),1);self.assertEqual(s.load(self.path)['events'][-1]['status'],'reserved')
        with self.assertRaises(AssertionError):s.remaining(self.root,dict(jobs=[self.job]))
    def test_identity_mismatch_stops_no_reissue(self):
        with self.assertRaises(ProviderError):self.run_job([GOOD],identity='wrong-model')
        self.assertEqual(len(self.sent),1);self.assertTrue(s.load(self.path)['halted'])
    def test_public_tool_failure_stops(self):
        result=evaluation(False,native='tool_error');result['shared_tool_error']=True
        with self.assertRaises(RuntimeError):self.run_job([GOOD],lambda *args:result)
        self.assertEqual(len(self.sent),1)
    def test_existing_request_never_replayed(self):
        folder=self.root/'jobs'/self.job['condition'];folder.mkdir(parents=True)
        (folder/(self.job['pid']+'.request_01.json')).write_text('{}')
        with self.assertRaises(AssertionError):self.run_job([GOOD])
        self.assertEqual(self.sent,[])
    def test_completed_job_skipped_on_resume(self):
        self.run_job([GOOD]);self.assertEqual(s.remaining(self.root,dict(jobs=[self.job])),{})
    def test_actual_cli_full_controller_local_only(self):
        self.job.update(framework='codex',condition='codex_deepseek-v4pro',job_id='codex_deepseek-v4pro/public-easy-01')
        self.pending={self.job['job_id']:4};r=self.run_job([GOOD])
        self.assertEqual(len(self.sent),1);self.assertTrue(r['job_done']);self.assertTrue(r['attempts'][0]['functional_pass'])

class PolicyTests(unittest.TestCase):
    def test_formal_violation_allows_one_repair(self):self.assertTrue(s.repairable(s.classify(evaluation(True,'violated'))))
    def test_formal_unsupported_does_not_trigger_repair(self):self.assertFalse(s.repairable(s.classify(evaluation(True,'inconclusive'))))
    def test_fifo_platform_limit_is_not_candidate_failure(self):
        a=s.classify(evaluation(True,'bounded_pass','unsupported_platform'))
        self.assertTrue(a['functional_pass']);self.assertFalse(a['native_pass']);self.assertFalse(a['native_eligible']);self.assertFalse(s.repairable(a))
    def test_fifo_function_failure_still_repairable(self):self.assertTrue(s.repairable(s.classify(evaluation(False,'not_run','unsupported_platform'))))
    def test_static_gate_uses_original_interface(self):
        good=(s.RELEASE/'datasets/public/tests/public-easy-01.reference.st').read_text(encoding='utf-8')
        result=s.run_stage(good,'public-easy-01','static',20)
        self.assertTrue(result['result']['compiles']);self.assertTrue(result['complete_code']);self.assertEqual(result['result']['tests_passed'],0)
    def test_pipeline_stage_order(self):
        calls=[]
        class Backend:
            timeout=120
            def __init__(self,cfg):pass
            def compile(self,source,problem):calls.append('native');return type('R',(),dict(to_dict=lambda self:dict(status='passed')))()
        def stage(source,pid,mode,remaining):
            calls.append(mode);r=evaluation(mode!='static');r['complete_code']=True
            return r
        with patch.object(s,'run_stage',side_effect=stage),patch.object(s.old.old.support,'CodesysBackend',Backend):
            s.evaluate(GOOD,'public-easy-01',{},time.monotonic()+1200)
        self.assertEqual(calls,['static','native','functional','bounded'])
    def test_fifo_pipeline_never_silently_substitutes_dint(self):
        source=(s.RELEASE/'datasets/public/tests/public-hard-04.reference.st').read_text(encoding='utf-8')
        with patch.object(s.old.old.support,'CodesysBackend',side_effect=AssertionError('Unsupported course interface must be separate')):
            result=s.evaluate(source,'public-hard-04',s.config(),time.monotonic()+1200)
        self.assertEqual(result['result']['tests_passed'],31)
        self.assertEqual(result['result']['platform_results']['codesys']['status'],'unsupported_platform')
    def test_full_plan_fits_new_authorization_and_preserves_coverage(self):
        cfg=s.config();plan=s.build_plan(cfg,s.load(cfg['budget_ledger_path']))
        self.assertEqual(len(plan['jobs']),140);self.assertEqual(plan['cases_per_arm'],946)
        self.assertEqual(len({j['job_id'] for j in plan['jobs']}),140)
        self.assertLessEqual(s.money(s.BASELINE)+s.money(plan['worst_reservation_cny']),s.money(190))
    def test_changed_model_api_parameters_or_prices_rejected(self):
        original=s.load;cfg=copy.deepcopy(s.config());cfg['models'][0]['base_url']='https://changed.invalid/v1'
        with patch.object(s,'load',side_effect=lambda p:cfg if Path(p)==s.CONFIG else original(p)):
            with self.assertRaises(AssertionError):s.config()

if __name__=='__main__':unittest.main()

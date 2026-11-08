"""Behavior, deadline, coverage and billing checks without external model calls."""
import copy
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO/'progress/tools'))
import r4_check_order as study
from stbench.evaluation import atomic_json
from stbench.providers.base import ProviderResponse,ProviderError
from stbench.schema import Problem
from stbench.transport import MeteredProvider

GOOD='FUNCTION_BLOCK FB VAR_INPUT x:BOOL; END_VAR VAR_OUTPUT y:BOOL; END_VAR y:=x; END_FUNCTION_BLOCK'
BAD=GOOD.replace('y:=x','y:=NOT x')


def tiny_problem():
    return Problem.from_dict(dict(pid='order-fixture',source='selfmade',difficulty='easy',title='copy',requirements='y=x',
        variables=[dict(name='x',data_type='BOOL',direction='input'),dict(name='y',data_type='BOOL',direction='output')],
        specs=[dict(sid='S1',text='copy',ltl='G(y = x)',kind='safety')],
        test_cases=[dict(tc_id='first',inputs=dict(x=False),expected=dict(y=False),expect_full=True)],
        mc_max_depth=3,mc_max_traces=100,mc_max_seconds=1))


class CheckOrder(unittest.TestCase):
    def inputs(self,directory):
        cfg=study.configuration(str(study.CONFIG));cfg=copy.deepcopy(cfg)
        cfg['platform_root']=directory;cfg['budget_ledger_path']=str(Path(directory)/'evidence/dmxapi_budget_75.json')
        cfg['campaign_root']=str(Path(directory)/'run')
        state=dict(version=3,limit_cny=75,spent_cny=37.756189,halted='',events=[dict(request_id='old',status='reserved',reserved_cny=.78450215)],recoveries=[])
        atomic_json(Path(cfg['budget_ledger_path']),state)
        return cfg,state

    def test_balanced_fixed_jobs(self):
        jobs=study.jobs();self.assertEqual(len(jobs),8);self.assertEqual(len({x['job_id'] for x in jobs}),8)
        for arm in {x['condition'] for x in jobs}:
            self.assertEqual({x['pid'] for x in jobs if x['condition']==arm},set(study.PIDS))
        self.assertEqual([x['condition'] for x in jobs[:4]],[x['condition'] for x in jobs[4:]][::-1])

    def test_selected_contracts_are_unchanged(self):
        self.assertEqual(set(study.selected()),set(study.PIDS))
        study.verify_r4()

    def test_all_initial_and_repair_calls_fit_budget(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state=self.inputs(directory);plan=study.plan_for(cfg,state)
            self.assertEqual(plan['maximum_new_requests'],16);self.assertLess(plan['worst_reservation_cny'],4.5)
            self.assertEqual(plan['cumulative_ceiling_cny'],42.256189)
            self.assertEqual(study.budget_for(cfg,plan).ceiling(),42.256189)

    def test_original_diagnostic_ceiling_is_never_extended(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state=self.inputs(directory);state['spent_cny']=43.9
            with self.assertRaises(RuntimeError):study.plan_for(cfg,state)
            state['spent_cny']=37.756189;state['halted']='unknown usage'
            with self.assertRaises(RuntimeError):study.plan_for(cfg,state)

    def test_forged_stage_cap_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state=self.inputs(directory);plan=study.plan_for(cfg,state)
            with self.assertRaises(RuntimeError):study.budget_for(cfg,plan|dict(cumulative_ceiling_cny=75))
            with self.assertRaises(RuntimeError):study.budget_for(cfg,plan|dict(study_additional_cap_cny=5))

    def test_only_verification_policy_changes_between_arms(self):
        cfg=study.configuration(str(study.CONFIG))
        for fw in ('custom','codex'):
            captured=[]
            class Capture:
                name='mock';model='offline-fixture';timeout=420
                def generate(self,messages):
                    captured.append(copy.deepcopy(messages))
                    return ProviderResponse(text=GOOD,model=self.model,usage=dict(prompt_tokens=1,completion_tokens=1))
            for after in (False,True):
                evaluator=lambda *args:study.StageResult(compiles=True,tests_total=1,tests_passed=1,
                    mc_executed=True,mc_specs_total=1,mc_specs_hold=1)
                solver=study.Solver(Capture(),max_iters=1,task_seconds=1200,request_window_seconds=450,
                    system_prompt=study.support.system_prompt(cfg,fw),verification_after_tests=after,evaluator=evaluator)
                study.solve_problem(tiny_problem(),solver)
            self.assertEqual(len(captured),2);self.assertEqual(captured[0],captured[1])

    def test_failed_functional_candidate_skips_only_tests_first_mc(self):
        p=tiny_problem()
        a=study.PolicyEvaluator(time.monotonic()+15,False)(p,BAD)
        b=study.PolicyEvaluator(time.monotonic()+15,True)(p,BAD)
        self.assertEqual((a.tests_passed,b.tests_passed),(0,0))
        self.assertTrue(a.mc_executed);self.assertGreater(a.mc_specs_violated,0)
        self.assertFalse(b.mc_executed)

    def test_passing_candidate_checked_in_both_arms(self):
        p=tiny_problem()
        for after in (False,True):
            r=study.PolicyEvaluator(time.monotonic()+15,after)(p,GOOD)
            self.assertTrue(r.all_tests_passed);self.assertTrue(r.mc_executed);self.assertTrue(r.specs_all_hold)

    def test_evaluator_honors_remaining_total_time(self):
        r=study.PolicyEvaluator(time.monotonic()-1,False)(tiny_problem(),GOOD)
        self.assertIn('timeout',r.mc_error)

    def test_real_r4_judge_in_offline_two_round_repair(self):
        for after in (False,True):
            class Scripted:
                name='mock';model='offline-fixture';timeout=420
                def __init__(self):self.calls=[]
                def generate(self,messages):
                    self.calls.append(copy.deepcopy(messages))
                    return ProviderResponse(text=BAD if len(self.calls)==1 else GOOD,model=self.model,
                        usage=dict(prompt_tokens=1,completion_tokens=1))
            provider=Scripted()
            solver=study.Solver(provider,max_iters=2,task_seconds=30,request_window_seconds=0,
                verification_after_tests=after,evaluator=study.PolicyEvaluator(time.monotonic()+30,after))
            record=study.solve_problem(tiny_problem(),solver)
            self.assertTrue(record.solved);self.assertFalse(record.first_try);self.assertEqual(len(provider.calls),2)
            self.assertEqual(sum(a.judge['model_check']['executed'] for a in record.attempts),1 if after else 2)

    def test_guard_protects_future_jobs_and_blocks_third_call(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state=self.inputs(directory);plan=study.plan_for(cfg,state);budget=study.budget_for(cfg,plan);calls=[]
            spec=next(x for x in cfg['models'] if x['id']=='minimax-m27')
            def sender(*args):
                calls.append(1)
                return dict(model=spec['model'],usage=dict(prompt_tokens=10,completion_tokens=20),
                    choices=[dict(finish_reason='stop',message=dict(content=GOOD))])
            provider=MeteredProvider(spec,budget,max_tokens=16384,offline=True,sender=sender)
            job=plan['jobs'][0];pending={job['job_id']:job['first_upper_cny']+job['repair_upper_cny'],'future':.4}
            study.support.guarded_capture(provider,budget,plan,job,pending,Path(directory))
            provider.generate([dict(role='user',content='task')]);self.assertGreater(budget.protected_cny,.4)
            provider.generate([dict(role='user',content='repair')]);self.assertAlmostEqual(budget.protected_cny,.4)
            with self.assertRaises(ProviderError):provider.generate([dict(role='user',content='third')])
            self.assertEqual(len(calls),2);self.assertEqual(budget.read()['events'][0],state['events'][0])

    def test_unknown_response_retains_reservation_and_halts(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state=self.inputs(directory);plan=study.plan_for(cfg,state);budget=study.budget_for(cfg,plan);calls=[]
            def sender(*args):calls.append(1);raise ProviderError('Unconfirmed upstream result')
            spec=next(x for x in cfg['models'] if x['id']=='minimax-m27')
            provider=MeteredProvider(spec,budget,max_tokens=16384,offline=True,sender=sender)
            job=plan['jobs'][0]
            study.support.guarded_capture(provider,budget,plan,job,{job['job_id']:1.},Path(directory))
            with self.assertRaises(ProviderError):provider.generate([dict(role='user',content='task')])
            actual=budget.read(allow_halted=True)
            self.assertEqual(calls,[1]);self.assertTrue(actual['halted']);self.assertEqual(actual['events'][-1]['status'],'reserved')
            self.assertEqual(actual['events'][0],state['events'][0])

    def test_partial_results_keep_all_planned_denominators(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state=self.inputs(directory);plan=study.plan_for(cfg,state);root=Path(cfg['campaign_root'])
            atomic_json(root/'ledger_before_study.json',state)
            s=study.collect(cfg,plan)
            self.assertEqual((s['recorded'],s['planned']),(0,8));self.assertTrue(s['all_original_events_preserved'])
            self.assertEqual(len(s['rows']),4);self.assertTrue(all(r['n']==2 and r['tests_total']>0 for r in s['rows']))


if __name__=='__main__':unittest.main()

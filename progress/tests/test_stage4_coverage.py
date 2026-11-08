"""First-candidate reuse and billing protections, without model API calls."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO/'progress/tools'))
import r9_stage4_coverage as study
from stbench.campaign import configuration
from stbench.evaluation import atomic_json,StageResult
from stbench.harness.engine import Solver,solve_problem
from stbench.providers.base import ProviderError,ProviderResponse
from stbench.schema import Problem
from stbench.transport import MeteredProvider


class Coverage(unittest.TestCase):
    def inputs(self,directory):
        cfg=configuration(str(study.CONFIG));cfg['platform_root']=directory
        cfg['budget_ledger_path']=str(Path(directory)/'evidence/dmxapi_budget_75.json')
        cfg['campaign_root']=str(Path(directory)/'run')
        state=dict(version=3,limit_cny=75,spent_cny=37.756189,halted='',events=[
            dict(request_id='old',status='reserved',reserved_cny=.78450215)])
        atomic_json(Path(cfg['budget_ledger_path']),state)
        return cfg,state

    def plan(self,cfg,state):
        descriptor=dict(source_record='fixture',source_record_sha256='h',first_attempt_sha256='f',source_run_signature='r')
        with patch.object(study,'validate_prefix_source'),patch.object(study,'reuse_descriptor',return_value=descriptor):
            return study.build_plan(cfg,state)

    def test_six_fixed_tasks_have_all_eight_reuses_and_sixteen_fresh_requests(self):
        jobs=study.make_jobs()
        self.assertEqual(len(jobs),24);self.assertEqual(len({j['job_id'] for j in jobs}),24)
        self.assertEqual(sum(j['kind']=='reused_first' for j in jobs),8)
        self.assertEqual(sum(j['kind']=='fresh' for j in jobs),16)
        for condition in {j['condition'] for j in jobs}:
            self.assertEqual({j['pid'] for j in jobs if j['condition']==condition},set(study.PILOT))

    def test_all_new_first_candidates_fit_the_inherited_ceiling(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state=self.inputs(directory);plan=self.plan(cfg,state)
            self.assertLess(plan['worst_reservation_cny'],6.2)
            self.assertEqual(plan['cumulative_ceiling_cny'],43.956189)
            budget=study.scoped_budget(cfg,plan)
            self.assertEqual(budget.ceiling(),43.956189)
            with self.assertRaises(RuntimeError):study.scoped_budget(cfg,plan|dict(cumulative_ceiling_cny=75))
            with self.assertRaises(RuntimeError):study.scoped_budget(cfg,plan|dict(study_additional_cap_cny=10))

    def test_reuse_takes_the_failed_first_attempt_even_when_repair_succeeded(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'old.json'
            atomic_json(source,dict(attempts=[dict(idx=0,code='first',solved=False),dict(idx=1,code='better repair',solved=True)]))
            desc=dict(source_record=str(source),source_record_sha256=study.sha(source),first_attempt_sha256='f',source_run_signature='r')
            job=dict(kind='reused_first',condition='arm',pid='p',**desc)
            with patch.object(study,'reuse_descriptor',return_value=desc):study.materialize_reuse({},dict(jobs=[job]),root/'run')
            out=json.loads((root/'run/reused/arm/p.json').read_text(encoding='utf-8'))
            self.assertEqual(out['first_attempt']['code'],'first');self.assertFalse(out['first_attempt']['solved'])
            self.assertEqual(out['new_model_requests'],0);self.assertNotIn('better repair',json.dumps(out))

    def test_single_call_guard_blocks_a_second_bill_and_protects_future_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state=self.inputs(directory);plan=self.plan(cfg,state);budget=study.scoped_budget(cfg,plan)
            calls=[];spec=cfg['models'][1]
            def sender(*args):
                calls.append(1)
                return dict(model=spec['model'],usage=dict(prompt_tokens=10,completion_tokens=20),
                    choices=[dict(finish_reason='stop',message=dict(content='FUNCTION_BLOCK FB END_FUNCTION_BLOCK'))])
            provider=MeteredProvider(spec,budget,max_tokens=16384,timeout=420,offline=True,sender=sender)
            job=dict(pid='p',job_id='arm/p',first_upper_cny=.3,repair_upper_cny=0.)
            study.capture(provider,budget,plan,job,{job['job_id']:.3,'future':.4},Path(directory)/'traces')
            provider.generate([dict(role='user',content='task')])
            self.assertAlmostEqual(budget.protected_cny,.4)
            with self.assertRaises(ProviderError):provider.generate([dict(role='user',content='second')])
            self.assertEqual(len(calls),1);self.assertEqual(len(budget.read()['events']),2)
            self.assertEqual(budget.read()['events'][0],state['events'][0])

    def test_unknown_result_keeps_reservation_and_does_not_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state=self.inputs(directory);plan=self.plan(cfg,state);budget=study.scoped_budget(cfg,plan);calls=[]
            def sender(*args):calls.append(1);raise ProviderError('Upstream RemoteDisconnected; no automatic retry')
            provider=MeteredProvider(cfg['models'][1],budget,max_tokens=16384,timeout=420,offline=True,sender=sender)
            job=dict(pid='p',job_id='arm/p',first_upper_cny=.3,repair_upper_cny=0.)
            study.capture(provider,budget,plan,job,{job['job_id']:.3},Path(directory)/'traces')
            with self.assertRaises(ProviderError):provider.generate([dict(role='user',content='task')])
            actual=budget.read(allow_halted=True)
            self.assertEqual(calls,[1]);self.assertTrue(actual['halted'])
            self.assertEqual(actual['events'][0],state['events'][0]);self.assertEqual(actual['events'][-1]['status'],'reserved')

    def test_partial_coverage_keeps_six_tasks_and_seventy_five_cases_per_group(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state=self.inputs(directory);plan=self.plan(cfg,state);root=Path(cfg['campaign_root'])
            atomic_json(root/'ledger_before_study.json',state)
            for job in plan['jobs']:
                if job['kind']=='reused_first':
                    atomic_json(root/'reused'/job['condition']/(job['pid']+'.json'),dict(first_attempt=dict(idx=0,solved=False)))
            summary=study.collect(cfg,plan)
            self.assertEqual((summary['recorded'],summary['planned'],summary['reused_count'],summary['fresh_recorded']),(8,24,8,0))
            self.assertTrue(all(r['n']==6 and r['tests_total']==75 for r in summary['rows']))
            self.assertTrue(summary['all_original_events_preserved'])
            job=next(j for j in plan['jobs'] if j['kind']=='fresh')
            atomic_json(root/'jobs'/job['condition']/(job['pid']+'.json'),dict(attempts=[{},{}]))
            with self.assertRaises(RuntimeError):study.collect(cfg,plan)

    def test_initial_prompt_is_independent_of_the_iteration_limit(self):
        p=Problem.from_dict(dict(pid='prefix',source='selfmade',difficulty='easy',title='prefix',requirements='out true',
            variables=[dict(name='out',data_type='BOOL',direction='output')],test_cases=[dict(tc_id='c',inputs={},expected={'out':True})]))
        seen=[]
        class Provider:
            model='fixture';name='mock';timeout=420
            def generate(self,messages):
                seen.append(copy.deepcopy(messages))
                return ProviderResponse(text='FUNCTION_BLOCK FB VAR_OUTPUT out:BOOL; END_VAR out:=TRUE; END_FUNCTION_BLOCK',
                    model=self.model,usage=dict(prompt_tokens=1,completion_tokens=1))
        def judge(*args):return StageResult(compiles=True,tests_total=1,tests_passed=1,mc_executed=True,mc_specs_total=1,mc_specs_hold=1)
        for maximum in (1,2):solve_problem(p,Solver(Provider(),max_iters=maximum,task_seconds=1200,request_window_seconds=450,evaluator=judge))
        self.assertEqual(len(seen),2);self.assertEqual(seen[0],seen[1])

    def test_reuse_binding_rejects_nonfirst_attempt_and_mismatched_mirror(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);cfg,_=self.inputs(directory)
            job=dict(pid='p',framework='custom',model_id='minimax-m27',condition='custom_minimax-m27',job_id='custom_minimax-m27/p')
            path=root/'prior/jobs/custom_minimax-m27/p.json';mirror=root/'progress/evidence/r9_four_group_stage3_20261101/jobs/custom_minimax-m27/p.json'
            data=dict(pid='p',model=cfg['models'][1]['model'],prompt_version=study.PROMPT_VERSION,experiment_kind='live',
                provider='openai-compat',run_signature='original',attempts=[dict(idx=0,code='first')])
            atomic_json(path,data);atomic_json(mirror,data)
            with patch.object(study,'PRIOR',root/'prior'),patch.object(study,'REPO',root):
                self.assertEqual(study.reuse_descriptor(job,cfg)['first_attempt_sha256'],study.object_sha(data['attempts'][0]))
                atomic_json(mirror,dict(changed=True))
                with self.assertRaises(RuntimeError):study.reuse_descriptor(job,cfg)
                data['attempts'][0]['idx']=1;atomic_json(path,data);atomic_json(mirror,data)
                with self.assertRaises(RuntimeError):study.reuse_descriptor(job,cfg)

    def test_frozen_materialized_reuse_cannot_be_replaced_by_a_better_result(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);record=root/'reused/arm/p.json'
            atomic_json(record,dict(first_attempt=dict(idx=0,solved=False)))
            atomic_json(root/'study_plan.json',dict(jobs=[]))
            atomic_json(root/'snapshot_manifest.json',dict(files={'tool':'hash'},reused_records={'reused/arm/p.json':study.sha(record)}))
            with patch.object(study.prior,'verify_frozen'),patch.object(study,'tool_manifest',return_value={'tool':'hash'}):
                study.verify_frozen(root)
                atomic_json(record,dict(first_attempt=dict(idx=1,solved=True)))
                with self.assertRaises(RuntimeError):study.verify_frozen(root)


if __name__=='__main__':unittest.main()

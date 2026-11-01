"""Observable specs must survive renaming and still reject behavioral defects."""
import copy
import json
from pathlib import Path
import re
import tempfile
import unittest
import sys
from unittest.mock import patch
import test_v2_request_windows as windows
from stbench.cli import problems, reference
from stbench.portability import adapt
from stbench.modelcheck import InputSpace, check
from stbench.evaluation import evaluate, StageResult
from stbench.harness.engine import Solver, solve_problem
from stbench.providers.base import ProviderError
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from r9_diagnostics import scoped_budget


class R9Policy(unittest.TestCase):
    def task(self, pid):
        p = next(p for p in problems() if p.pid == pid)
        return adapt(p, reference(p), 'codesys')[:2]

    def ipv4_check(self, source):
        p, _ = self.task('public-medium-08')
        return check(source, [(s.sid,s.ltl) for s in p.specs if s.ltl],
            InputSpace({'ipText':['0.0.0.0','1.2.3.4','255.255.255.255','1.2.3','1.2.3.256','01.2.3.4']}),
            observer_name='ipv4', observable_names={v.name for v in p.variables},
            max_depth=2, max_traces=1000, max_seconds=5)

    def test_ipv4_private_variable_renaming_keeps_the_same_verdict(self):
        _, source = self.task('public-medium-08')
        renamed = re.sub(r'\bsegCount\b','renamedSegments',source)
        renamed = re.sub(r'\bok\b','renamedValidFlag',renamed)
        first, second = self.ipv4_check(source), self.ipv4_check(renamed)
        self.assertFalse(first.error)
        self.assertTrue(first.all_hold)
        self.assertTrue(second.all_hold)
        self.assertEqual([(s.spec_id,s.holds) for s in first.specs],[(s.spec_id,s.holds) for s in second.specs])

    def test_ipv4_wrong_byte_order_or_constant_output_is_not_accepted(self):
        _, source = self.task('public-medium-08')
        source = source.replace('END_FUNCTION_BLOCK', 'ipValue := UDINT#0; END_FUNCTION_BLOCK')
        self.assertTrue(self.ipv4_check(source).contradictions)

    def test_private_spec_is_inconclusive_even_if_candidate_uses_the_reference_name(self):
        for variable in ('hidden','renamed'):
            src = f'FUNCTION_BLOCK FB VAR_INPUT a:BOOL; END_VAR VAR_OUTPUT b:BOOL; END_VAR VAR {variable}:BOOL; END_VAR b:=a; END_FUNCTION_BLOCK'
            report = check(src, {'public':'G(b = a)','private':'G(hidden = FALSE)'},
                InputSpace({'a':[False,True]}),observable_names={'a','b'},max_depth=2,max_traces=30)
            self.assertFalse(report.error)
            results={s.spec_id:s for s in report.specs}
            self.assertTrue(results['public'].holds)
            self.assertTrue(results['private'].inconclusive)
            self.assertFalse(report.all_hold)

    def test_reserved_observer_names_cannot_be_supplied_by_candidate(self):
        _, source = self.task('public-medium-08')
        source=source.replace('VAR_OUTPUT','VAR __spec_ip_valid:BOOL; END_VAR VAR_OUTPUT')
        self.assertIn('reserved',self.ipv4_check(source).error)

    def test_process_observer_survives_arbitrary_candidate_state_names(self):
        p,source=self.task('public-hard-02')
        for name in ['phase','idx','curStation','dstStation','compEdge']:
            source=re.sub(r'\b'+name+r'\b','candidate_'+name,source)
        report=check(source,[(s.sid,s.ltl) for s in p.specs],
            InputSpace({'processLength':[2],'processSequence':[[2,5,0,0,0,0,0,0]],'sensor1':[True],
                        'station1Start':[False,True],'sensor2':[False,True],'sensor5':[False,True],
                        'station2Complete':[False,True]}),observer_name='process',
            observable_names={v.name for v in p.variables},max_depth=4,max_traces=500,max_seconds=3)
        self.assertFalse(report.error)
        self.assertFalse(report.contradictions)
        self.assertEqual(len(report.specs),7)

    def test_process_wrong_direction_is_detected(self):
        p,source=self.task('public-hard-02')
        source=source.replace('END_FUNCTION_BLOCK','conveyorRight := FALSE; END_FUNCTION_BLOCK')
        report=check(source,[(s.sid,s.ltl) for s in p.specs],
            InputSpace({'processLength':[1],'processSequence':[[5,0,0,0,0,0,0,0]],'sensor1':[True],
                        'station1Start':[True],'sensor5':[False]}),observer_name='process',
            observable_names={v.name for v in p.variables},max_depth=2,max_traces=20)
        self.assertTrue(report.contradictions)

    def test_invalid_caller_history_cannot_later_be_counted_as_in_contract(self):
        from stbench.spec_observers import process
        initial=process({},initial=True)
        invalid=process(dict(processlength=1,processsequence=[0]*8),initial)
        valid_input=dict(processlength=1,processsequence=[5,0,0,0,0,0,0,0],sensor1=True,station1start=True)
        self.assertFalse(process(valid_input,invalid)['__spec_contract'])
        self.assertTrue(process(valid_input,initial)['__spec_contract'])

    def test_original_dataset_and_case_assertions_are_not_edited_by_overlay(self):
        for p in problems():
            original=copy.deepcopy(p.to_dict())
            adapted,_=self.task(p.pid)
            self.assertEqual(p.to_dict(),original)
            self.assertEqual([c.expected for c in adapted.test_cases],[c.expected for c in p.test_cases])
        specs=[s for p in problems() for s in self.task(p.pid)[0].specs]
        self.assertEqual(sum(bool(s.ltl) for s in specs),179)
        self.assertEqual(sum(not s.ltl for s in specs),24)

    def test_failed_functional_tests_skip_expensive_model_check(self):
        p=windows.problem()
        source='FUNCTION_BLOCK FB VAR_OUTPUT out:BOOL; END_VAR out:=FALSE; END_FUNCTION_BLOCK'
        result=evaluate(source,p,model_check=True,verification_after_tests=True,timeout_s=3)
        self.assertTrue(result.compiles)
        self.assertEqual(result.tests_passed,0)
        self.assertFalse(result.mc_executed)

    def test_1200_seconds_allows_a_second_full_request_without_shortening_timeout(self):
        with tempfile.TemporaryDirectory() as directory:
            helper=windows.RequestWindows();clock=windows.Clock()
            provider,_,calls=helper.provider(directory,clock,[290,10])
            def judge(*args):
                return StageResult(compiles=True,tests_total=1,tests_passed=int(len(calls)==2),
                    mc_executed=len(calls)==2,mc_specs_total=int(len(calls)==2),mc_specs_hold=int(len(calls)==2))
            solver=Solver(provider,max_iters=5,task_seconds=1200,request_window_seconds=450,
                          verification_after_tests=True,evaluator=judge)
            with patch('stbench.harness.engine.time.monotonic',clock.monotonic):
                record=solve_problem(windows.problem(),solver)
            self.assertEqual(calls,[420,420])
            self.assertTrue(record.solved)

    def test_incomplete_body_is_recorded_without_refunding_or_accepting_it(self):
        with tempfile.TemporaryDirectory() as directory:
            helper=windows.RequestWindows();provider,budget,_=helper.provider(directory,windows.Clock(),[])
            body=dict(model='window-fixture',usage=dict(prompt_tokens=10,completion_tokens=20),
                choices=[dict(finish_reason='length',message=dict(content='<think>unfinished'))])
            provider.sender=lambda *args:body
            observed=[];provider.response_observer=lambda data,protocol:observed.append((data,protocol))
            with self.assertRaises(ProviderError):provider.generate([dict(role='user',content='task')])
            self.assertEqual(observed,[(body,'chat')])
            self.assertEqual(budget.snapshot()['events'][0]['status'],'settled')
            self.assertFalse(budget.snapshot()['halted'])

    def test_new_arithmetic_formulas_reject_mutations_and_accept_references(self):
        cases=[('self-easy-01','S4',{'enable':[True],'avgEnable':[True],'count':[1,2,8,9],
                 'values':[[1,2,3,4,5,6,7,8]]},'avgOut := -99.0;'),
               ('self-medium-05','S8',{'enable':[True],'resetBtn':[False,True],'scanSeconds':[1.0],
                 'steamFlow':[1.0],'fuelFlow':[1.0],'steamTemp':[450.0],'steamPressure':[3800.0]},'revenue := -99.0;'),
               ('self-medium-06','S6',{'enable':[True],'resetBtn':[False],'sensorValid':[True],
                 'setpoint':[50.0],'temperature':[50.0],'scanSeconds':[1.0],'bias':[20.0]},'power := 101.0;')]
        for pid,sid,domains,mutation in cases:
            p,source=self.task(pid);formula=next(s.ltl for s in p.specs if s.sid==sid)
            with self.subTest(pid=pid):
                report=check(source,{sid:formula},InputSpace(domains),max_depth=2,max_traces=300,max_seconds=3,
                             observable_names={v.name for v in p.variables})
                self.assertTrue(report.all_hold,report.to_dict())
                changed=source.replace('END_FUNCTION_BLOCK',mutation+' END_FUNCTION_BLOCK')
                report=check(changed,{sid:formula},InputSpace(domains),max_depth=2,max_traces=300,max_seconds=3,
                             observable_names={v.name for v in p.variables})
                self.assertTrue(report.contradictions)

    def test_diagnostic_cap_preserves_history_and_blocks_an_over_cap_request(self):
        from stbench.campaign import configuration
        from stbench.evaluation import atomic_json
        with tempfile.TemporaryDirectory() as directory:
            cfg=configuration('');root=Path(directory);ledger=root/'evidence/dmxapi_budget_75.json'
            cfg.update(platform_root=directory,budget_ledger_path=str(ledger))
            state=dict(version=3,limit_cny=75,spent_cny=34.0,halted='',events=[
                dict(request_id='unknown',status='reserved',reserved_cny=.4)])
            atomic_json(ledger,state)
            plan=dict(incremental_cap_cny=10,total_authorized_cny=75,baseline_spent_cny=34.,cumulative_ceiling_cny=44.)
            budget=scoped_budget(cfg,plan)
            index=budget.reserve(9.9);before=ledger.read_bytes()
            with self.assertRaises(ProviderError):budget.reserve(.11)
            self.assertEqual(ledger.read_bytes(),before)
            self.assertEqual(budget.snapshot()['events'][0],state['events'][0])
            self.assertEqual(budget.snapshot()['spent_cny'],43.9)
            with self.assertRaises(RuntimeError):scoped_budget(cfg,plan|dict(cumulative_ceiling_cny=75))


if __name__=='__main__':unittest.main()

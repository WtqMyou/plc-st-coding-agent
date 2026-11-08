import copy
import subprocess
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO/'progress/v13_r3'))
import r3_revision as v
import r3_judge as judge
from stbench.schema import Problem
from stbench.platforms import CompileResult


class NativeFixture:
    def __init__(self,status='passed',name='codesys',raises=False):
        self.name=name;self.timeout=30;self.status=status;self.raises=raises;self.calls=0
    def compile(self,source,problem):
        self.calls+=1
        if self.raises:raise OSError('fixture tool failure')
        return CompileResult(self.name,self.status)


def fixture(body,dtype='INT',expected=10,full=False):
    p=Problem.from_dict(dict(pid='string-fixture',source='selfmade',difficulty='easy',title='fixture',requirements='type semantics',
        variables=[dict(name='text',data_type='STRING(20)',direction='input'),dict(name='value',data_type=dtype,direction='output')],
        test_cases=[dict(tc_id='q1',inputs={'text':'9'},expected={'value':expected},expect_full=full)]))
    code=f'FUNCTION_BLOCK FB VAR_INPUT text:STRING(20); END_VAR VAR_OUTPUT value:{dtype}; END_VAR {body} END_FUNCTION_BLOCK'
    return p,code


class R3Tests(unittest.TestCase):
    def test_historical_candidate_is_static_error_not_python_exception(self):
        p=next(p for p in v.problems() if p.pid=='public-medium-08');q,_,_=v.adapt(p);source=v.historical_candidate()
        result=judge.local_tests(source,q)
        self.assertFalse(result.compiles);self.assertEqual(result.tests_total,12)
        self.assertIn('E_ARITH_TYPE',[d['code'] for d in result.compile_errors])
        self.assertEqual(result.evidence_metadata['classification'],'candidate_static_error')
        self.assertFalse(result.mc_error)

    def test_mid_subtraction_rejected_in_local_and_worker_entrypoints(self):
        p,source=fixture("value:=MID(text,1,1)-'0';")
        with patch('r3_judge.parent.local_tests') as local,patch('r3_judge.parent.evaluate') as worker:
            self.assertFalse(judge.local_tests(source,p).compiles)
            self.assertFalse(judge.evaluate(source,p,backends=(SimpleNamespace(name='codesys'),)).compiles)
            local.assert_not_called();worker.assert_not_called()

    def test_numeric_ops_reject_known_string_operands(self):
        for expression in ["MID(text,1,1)*2","MID(text,1,1)/2","MID(text,1,1) MOD 2","2+MID(text,1,1)","-MID(text,1,1)"]:
            p,source=fixture('value:='+expression+';')
            self.assertIn('E_ARITH_TYPE',[d['code'] for d in judge.local_tests(source,p).compile_errors])

    def test_string_variable_arithmetic_rejected(self):
        p,source=fixture("value:=text-'0';")
        self.assertFalse(judge.local_tests(source,p).compiles)

    def test_explicit_numeric_conversion_runs(self):
        p,source=fixture('value:=STRING_TO_INT(MID(text,1,1))+1;')
        self.assertTrue(judge.local_tests(source,p).all_tests_passed)

    def test_string_comparison_runs(self):
        p,source=fixture("value:=MID(text,1,1)>='0';",'BOOL',True)
        self.assertTrue(judge.local_tests(source,p).all_tests_passed)

    def test_concat_function_runs_in_both_profiles(self):
        p,source=fixture("value:=CONCAT(MID(text,1,1),'x');",'STRING(20)','9x')
        for profile in ('codesys','openplc'):
            self.assertTrue(judge.local_tests(source,p,profile=profile).all_tests_passed)

    def test_string_plus_is_platform_specific(self):
        p,source=fixture("value:=MID(text,1,1)+'x';",'STRING(20)','9x')
        self.assertFalse(judge.local_tests(source,p,profile='codesys').compiles)
        self.assertTrue(judge.local_tests(source,p,profile='openplc').all_tests_passed)

    def test_openplc_arithmetic_not_claimed_as_native_failure(self):
        p,source=fixture("value:=MID(text,1,1)-'0';")
        r=judge.evaluate(source,p,backends=(NativeFixture(name='openplc'),))
        self.assertEqual(r.evidence_metadata['classification'],'unsupported_modeling')
        self.assertTrue(r.mc_error.startswith('Unsupported modeling:'))
        self.assertTrue(r.evidence_metadata['native_compilation_claimed'])
        self.assertEqual(r.platform_results['openplc']['status'],'passed')

    def test_valid_byte_index_not_misclassified_as_bad_string_arithmetic(self):
        p,source=fixture('value:=text[1]-BYTE#48;',expected=9)
        static,_=judge.check_source(source)
        self.assertTrue(static.ok)
        r=judge.local_tests(source,p)
        self.assertEqual(r.evidence_metadata['classification'],'unsupported_modeling')
        self.assertNotIn('E_ARITH_TYPE',[d['code'] for d in r.compile_errors])

    def test_test_contract_gate_still_precedes_source_checks(self):
        p,source=fixture("value:=MID(text,1,1)-'0';",full=True);p.test_cases[0].expected={}
        r=judge.local_tests(source,p)
        self.assertEqual(r.compile_errors[0]['code'],'E_TEST_CONTRACT')
        self.assertFalse(r.evidence_metadata['candidate_evaluated'])

    def test_parent_and_data_are_not_mutated(self):
        p,source=fixture('value:=STRING_TO_INT(MID(text,1,1))+1;');before=copy.deepcopy(p.to_dict())
        judge.local_tests(source,p);self.assertEqual(before,p.to_dict());v.verify_parent()

    def test_valid_worker_still_runs(self):
        p,source=fixture('value:=STRING_TO_INT(MID(text,1,1))+1;')
        r=judge.evaluate(source,p,model_check=False,timeout_s=4)
        self.assertTrue(r.all_tests_passed);self.assertEqual(r.evidence_metadata['judge_version'],judge.JUDGE_VERSION)

    def test_profile_cannot_silently_mismatch_openplc_native_run(self):
        p,source=fixture('value:=1;')
        with self.assertRaises(ValueError):judge.evaluate(source,p,profile='codesys',backends=(SimpleNamespace(name='openplc'),))
        with self.assertRaises(ValueError):judge.evaluate(source,p,profile='openplc',backends=(SimpleNamespace(name='codesys'),))

    def test_adapted_task_platform_controls_default_profile(self):
        p,source=fixture("value:=MID(text,1,1)+'x';",'STRING(20)','9x')
        p.provenance['platform_adaptation']={'platform':'openplc'}
        self.assertTrue(judge.local_tests(source,p).all_tests_passed)

    def test_native_failure_resolves_boundary_without_simulation(self):
        p,source=fixture('value:=text[1]-BYTE#48;',expected=9);backend=NativeFixture('failed')
        r=judge.evaluate(source,p,backends=(backend,),timeout_s=2)
        self.assertEqual(r.evidence_metadata['classification'],'candidate_native_error')
        self.assertFalse(r.mc_error);self.assertEqual(r.tests_passed,0);self.assertEqual(backend.timeout,30)

    def test_native_success_does_not_prove_local_semantics(self):
        p,source=fixture('value:=text[1]-BYTE#48;',expected=9);backend=NativeFixture('passed')
        r=judge.evaluate(source,p,backends=(backend,))
        self.assertEqual(r.evidence_metadata['classification'],'unsupported_modeling')
        self.assertEqual(r.tests_passed,0);self.assertFalse(r.all_tests_passed)

    def test_native_boundary_honors_zero_deadline(self):
        p,source=fixture('value:=text[1]-BYTE#48;',expected=9);backend=NativeFixture('failed')
        r=judge.evaluate(source,p,backends=(backend,),task_remaining_s=0)
        self.assertEqual(backend.calls,0)
        self.assertEqual(r.evidence_metadata['classification'],'tool_error')
        self.assertIn('timeout',r.mc_error)

    def test_native_tool_error_stays_unresolved_and_restores_timeout(self):
        p,source=fixture('value:=text[1]-BYTE#48;',expected=9);backend=NativeFixture(raises=True)
        r=judge.evaluate(source,p,backends=(backend,),timeout_s=1)
        self.assertEqual(r.platform_results['codesys']['status'],'tool_error')
        self.assertEqual(r.evidence_metadata['classification'],'unsupported_modeling');self.assertEqual(backend.timeout,30)

    def test_static_worker_timeout_never_reaches_main_judge(self):
        p,source=fixture('value:=1;')
        with patch('r3_judge.subprocess.run',side_effect=subprocess.TimeoutExpired('fixture',1)),patch('r3_judge.parent.evaluate') as later:
            r=judge.evaluate(source,p,timeout_s=1)
            self.assertIn('timeout',r.mc_error);later.assert_not_called()

    def test_all_project_references_still_pass(self):
        results=[judge.local_tests(source,q) for p in v.problems() for q,source,_ in [v.adapt(p)]]
        self.assertTrue(all(r.compiles and r.all_tests_passed for r in results))
        self.assertEqual(sum(r.tests_passed for r in results),531)


if __name__=='__main__':unittest.main()

import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO/'progress/v13_r2'))
import r2_revision as v
import r2_judge as judge
from stbench.schema import Problem
from stbench.evaluation import local_tests as legacy_local

SOURCE = 'FUNCTION_BLOCK FB VAR_OUTPUT a:BOOL; b:BOOL; END_VAR a:=TRUE; b:=FALSE; END_FUNCTION_BLOCK'


def task(mode='sequence', full=True, expected=None):
    return Problem.from_dict(dict(pid='full-output-probe', source='selfmade', difficulty='easy', title='probe', requirements='assert outputs',
        case_mode=mode, variables=[dict(name='a',data_type='BOOL',direction='output'),dict(name='b',data_type='BOOL',direction='output')],
        test_cases=[dict(tc_id='q1',inputs={},expected={'a':True} if expected is None else expected,expect_full=full)]))


class R2Tests(unittest.TestCase):
    def test_missing_output_rejected_in_both_modes(self):
        for mode in ('single','sequence'):
            r = judge.local_tests(SOURCE, task(mode))
            self.assertFalse(r.compiles)
            self.assertEqual(r.compile_errors[0]['code'], 'E_TEST_CONTRACT')
            self.assertFalse(r.evidence_metadata['candidate_evaluated'])

    def test_preflight_blocks_local_execution(self):
        with patch('r2_judge.base.local_tests') as base:
            judge.local_tests(SOURCE, task())
            base.assert_not_called()

    def test_preflight_blocks_worker_native_and_cache_entrypoint(self):
        with patch('r2_judge.base.evaluate') as base:
            r = judge.evaluate(SOURCE, task(), model_check=True, backends=(object(),))
            base.assert_not_called()
            self.assertFalse(r.evidence_metadata['test_contract_valid'])

    def test_complete_assertions_pass_both_modes(self):
        for mode in ('single','sequence'):
            self.assertTrue(judge.local_tests(SOURCE, task(mode,expected={'a':True,'b':False})).all_tests_passed)

    def test_explicit_partial_assertions_remain_valid(self):
        self.assertTrue(judge.local_tests(SOURCE, task(full=False)).all_tests_passed)

    def test_inout_is_part_of_full_output_contract(self):
        p = task();p.variables[1].direction = type(p.variables[1].direction).INOUT
        self.assertEqual(judge.prepare(p)[1].compile_errors[0]['code'], 'E_TEST_CONTRACT')

    def test_mixed_modes_are_all_checked(self):
        p = task('single', expected={'a':True,'b':False})
        c = copy.deepcopy(p.test_cases[0]);c.tc_id='q2';c.mode='sequence';c.expected={'a':True};p.test_cases.append(c)
        self.assertEqual(judge.prepare(p)[1].evidence_metadata['issues'][0]['tc_id'], 'q2')

    def test_case_insensitive_full_assertions_and_no_mutation(self):
        p = task('single', expected={'A':True,'B':False});before=copy.deepcopy(p.to_dict())
        self.assertTrue(judge.local_tests(SOURCE,p).all_tests_passed)
        self.assertEqual(p.to_dict(),before)

    def test_bad_expected_value_still_fails(self):
        self.assertFalse(judge.local_tests(SOURCE, task(expected={'a':False,'b':False})).all_tests_passed)

    def test_q45_isolates_invalid_sensor_reset_condition(self):
        p=next(p for p in v.problems() if p.pid=='self-hard-06')
        c=next(c for c in p.test_cases if c.tc_id=='q45')
        self.assertFalse(c.inputs['runRequest']);self.assertFalse(c.inputs['pressureValid'])
        self.assertTrue(c.inputs['resetBtn']);self.assertEqual(c.expected['currentCauseMask'],0)
        q,source,_=v.adapt(p)
        bad=source.replace('AND NOT runRequest AND pressureValid\n','AND NOT runRequest\n')
        self.assertNotEqual(source,bad)
        old=next(p for p in v.r1.problems() if p.pid=='self-hard-06')
        oldq,_,_=v.r1.adapt(old)
        self.assertTrue(legacy_local(bad,oldq).all_tests_passed)
        result=judge.local_tests(bad,q)
        self.assertEqual([c.tc_id for c in result.cases if not c.passed],['q45'])

    def test_all_reference_cases_pass_with_new_gate(self):
        rows=[judge.local_tests(source,q) for p in v.problems() for q,source,_ in [v.adapt(p)]]
        self.assertTrue(all(r.compiles and r.all_tests_passed for r in rows))
        self.assertEqual(sum(r.tests_total for r in rows),531)

    def test_model_check_worker_uses_validated_contract(self):
        result=judge.evaluate(SOURCE,task(expected={'a':True,'b':False}),model_check=False,timeout_s=4)
        self.assertTrue(result.all_tests_passed)
        self.assertTrue(result.evidence_metadata['test_contract_valid'])
        self.assertEqual(result.evidence_metadata['judge_version'],judge.JUDGE_VERSION)


if __name__ == '__main__': unittest.main()

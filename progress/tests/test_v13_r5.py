"""Conversion and scan-return behavior, isolation and bounded-entrypoint regressions."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import time
import unittest

REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO/'progress/v13_r5'))
import r5_revision as v
import r5_judge as judge
from conversions import checked,convert,bounds,runtime,UnsupportedConversion,INTEGER_TYPES
from stbench.schema import Problem
from stbench.st.frontend import compile_st
from stbench.st.interp import Interpreter as OldInterpreter
from stbench.st.typecheck import check_st as old_check


def problem(src='DINT',dst='INT',values=((3,3),)):
    return Problem.from_dict(dict(pid='generic-conversion',source='selfmade',difficulty='easy',title='convert',requirements='convert the input',
        variables=[dict(name='inputValue',data_type=src,direction='input'),dict(name='outputValue',data_type=dst,direction='output')],
        test_cases=[dict(tc_id='c'+str(i),inputs=dict(inputValue=x),expected=dict(outputValue=y),expect_full=True) for i,(x,y) in enumerate(values)],
        mc_max_depth=2,mc_max_traces=100,mc_max_seconds=1))


def code(src='DINT',dst='INT',expression=None):
    return (f'FUNCTION_BLOCK FB VAR_INPUT inputValue:{src}; END_VAR VAR_OUTPUT outputValue:{dst}; END_VAR '
            f'outputValue:={expression or "TO_"+dst+"(inputValue)"}; END_FUNCTION_BLOCK')


class Conversions(unittest.TestCase):
    def test_real_fifo_original_passes_without_rewrite(self):
        path=REPO/'progress/evidence/r4_check_order_20261108/jobs/codex_always_mc/public-hard-04.json'
        original=json.loads(path.read_text('utf-8'))['attempts'][1]
        p=next(p for p in v.problems() if p.pid=='public-hard-04');q,_,_=v.adapt(p)
        for profile in ('codesys','openplc'):
            r=judge.local_tests(original['code'],q,profile=profile)
            self.assertEqual((r.tests_passed,r.tests_total),(27,27));self.assertTrue(r.compiles)
            self.assertEqual(r.evidence_metadata['candidate_source_sha256'],original['code_hash'])
            self.assertFalse(r.evidence_metadata['candidate_text_rewritten'])

    def test_conversion_only_ablation_keeps_old_return_failure(self):
        original=json.loads((REPO/'progress/evidence/r4_check_order_20261108/jobs/codex_always_mc/public-hard-04.json').read_text('utf-8'))['attempts'][1]
        p=next(p for p in v.problems() if p.pid=='public-hard-04');q,_,_=v.adapt(p)
        r=runtime('codesys',False).evaluation.local_tests(original['code'],q)
        self.assertEqual((r.tests_passed,r.tests_total),(23,27))
        self.assertIn('h04-16',[c.tc_id for c in r.cases if not c.passed])

    def test_generic_target_has_exact_type(self):
        parsed,checker=checked(compile_st(code('INT','DINT')))
        self.assertTrue(parsed.ok)
        self.assertEqual(parsed.pou.body[0].args[1].typ,'DINT')
        self.assertEqual(checker.conversions[0]['source_type'],'INT')

    def test_integer_boundaries(self):
        for target in INTEGER_TYPES:
            lo,hi=bounds(target)
            src='LINT' if lo<0 else 'ULINT'
            p=problem(src,target,((lo,lo),(hi,hi),(0,0)))
            r=judge.local_tests(code(src,target),p)
            self.assertEqual((r.tests_passed,r.tests_total),(3,3),target)

    def test_bool_to_integer_and_integer_to_bool(self):
        r=judge.local_tests(code('BOOL','INT'),problem('BOOL','INT',((False,0),(True,1))))
        self.assertTrue(r.all_tests_passed)
        r=judge.local_tests(code('DINT','BOOL'),problem('DINT','BOOL',((-7,True),(0,False),(8,True))))
        self.assertTrue(r.all_tests_passed)

    def test_large_integer_keeps_exact_precision(self):
        value=2**53+1
        r=judge.local_tests(code('ULINT','LINT'),problem('ULINT','LINT',((value,value),)))
        self.assertTrue(r.all_tests_passed)

    def test_case_insensitive_and_nested_calls(self):
        p=problem('DINT','INT',((-3,-2),(3,4)))
        r=judge.local_tests(code(expression='to_iNt(TO_DINT(inputValue + 1))'),p)
        self.assertTrue(r.all_tests_passed)

    def test_array_index_conversion(self):
        p=Problem.from_dict(dict(pid='index',source='selfmade',difficulty='easy',title='index',requirements='lookup',
            variables=[dict(name='inputValue',data_type='DINT',direction='input'),dict(name='outputValue',data_type='INT',direction='output')],
            test_cases=[dict(tc_id='c',inputs=dict(inputValue=2),expected=dict(outputValue=9))]))
        src='FUNCTION_BLOCK FB VAR_INPUT inputValue:DINT; END_VAR VAR_OUTPUT outputValue:INT; END_VAR VAR data:ARRAY[1..3] OF INT; END_VAR data[1]:=7; data[2]:=9; data[3]:=11; outputValue:=data[TO_INT(inputValue)]; END_FUNCTION_BLOCK'
        self.assertTrue(judge.local_tests(src,p).all_tests_passed)

    def test_unknown_generic_function_stays_error(self):
        r=judge.local_tests(code(expression='TO_INVENTED(inputValue)'),problem())
        self.assertEqual(r.evidence_metadata['classification'],'candidate_static_error')
        self.assertIn('E_UNKNOWN_FUNC',[e['code'] for e in r.compile_errors])

    def test_wrong_conversion_arity(self):
        for expression in ('TO_INT()','TO_INT(inputValue, 2)'):
            r=judge.local_tests(code(expression=expression),problem())
            self.assertEqual(r.evidence_metadata['classification'],'candidate_static_error')
            self.assertIn('E_ARG_COUNT',[e['code'] for e in r.compile_errors])

    def test_undeclared_operand_is_not_hidden_as_unsupported(self):
        r=judge.local_tests(code(expression='TO_INT(missingValue)'),problem())
        self.assertIn('E_UNDECLARED',[e['code'] for e in r.compile_errors])

    def test_float_and_string_conversion_are_explicitly_unmodeled(self):
        for dtype,value in [('REAL',1.5),('STRING','12')]:
            r=judge.local_tests(code(dtype,'INT'),problem(dtype,'INT',((value,12),)))
            self.assertEqual(r.evidence_metadata['classification'],'unsupported_modeling')
            self.assertFalse(r.all_tests_passed);self.assertFalse(r.compile_errors)

    def test_out_of_range_is_unmodeled_not_a_false_success(self):
        for value in (-32769,32768):
            r=judge.local_tests(code(),problem(values=((value,0),)))
            self.assertEqual(r.evidence_metadata['classification'],'unsupported_modeling')
            self.assertIn('range',r.mc_error);self.assertFalse(r.all_tests_passed)

    def test_invalid_runtime_source_range_guard(self):
        with self.assertRaises(UnsupportedConversion):convert(50000,'INT','DINT')
        with self.assertRaises(UnsupportedConversion):convert(1.2,'DINT','INT')

    def test_new_modules_do_not_patch_old_judge(self):
        import r4_judge
        source=code();p=problem();original_call=OldInterpreter._call
        before=r4_judge.local_tests(source,p)
        self.assertFalse(before.compiles)
        self.assertTrue(judge.local_tests(source,p).all_tests_passed)
        self.assertIs(OldInterpreter._call,original_call)
        self.assertFalse(old_check(source).ok)
        self.assertFalse(r4_judge.local_tests(source,p).compiles)

    def test_full_output_guard_survives(self):
        p=problem();p.test_cases[0].expected={}
        r=judge.local_tests(code(),p)
        self.assertFalse(r.evidence_metadata['test_contract_valid'])
        self.assertFalse(r.evidence_metadata['candidate_evaluated'])

    def test_input_problem_is_not_mutated(self):
        p=problem();before=copy.deepcopy(p.to_dict())
        judge.local_tests(code(),p)
        self.assertEqual(p.to_dict(),before)

    def test_existing_string_arithmetic_guard(self):
        src=code('STRING','INT',"MID(inputValue,1,1) - '0'")
        r=judge.local_tests(src,problem('STRING','INT',(('12',1),)))
        self.assertIn('E_ARITH_TYPE',[e['code'] for e in r.compile_errors])


class Returns(unittest.TestCase):
    def run_source(self,body,values):
        p=problem('BOOL','INT',values);p.case_mode='sequence'
        source=code('BOOL','INT',body) if ':=' not in body else ('FUNCTION_BLOCK FB VAR_INPUT inputValue:BOOL; END_VAR VAR_OUTPUT outputValue:INT; END_VAR VAR i:INT; END_VAR '+body+' END_FUNCTION_BLOCK')
        return judge.local_tests(source,p)

    def test_return_stops_scan_and_next_scan_still_runs(self):
        r=self.run_source('outputValue:=outputValue+1; IF inputValue THEN RETURN; END_IF; outputValue:=outputValue+10;',((True,1),(False,12),(True,13)))
        self.assertTrue(r.all_tests_passed)

    def test_return_unwinds_for_while_repeat_and_case(self):
        bodies=[
            'FOR i:=1 TO 3 DO outputValue:=1; RETURN; END_FOR; outputValue:=99;',
            'WHILE TRUE DO outputValue:=1; RETURN; END_WHILE; outputValue:=99;',
            'REPEAT outputValue:=1; RETURN; UNTIL FALSE END_REPEAT; outputValue:=99;',
            'CASE inputValue OF TRUE: outputValue:=1; RETURN; ELSE outputValue:=2; END_CASE; outputValue:=99;']
        for body in bodies:self.assertTrue(self.run_source(body,((True,1),)).all_tests_passed,body)

    def test_exit_remains_loop_exit(self):
        r=self.run_source('FOR i:=1 TO 3 DO outputValue:=1; EXIT; END_FOR; outputValue:=99;',((True,99),))
        self.assertTrue(r.all_tests_passed)

    def test_conditional_return_not_silently_treated_as_unconditional(self):
        r=self.run_source('outputValue:=1; RETURN(inputValue); outputValue:=99;',((False,99),))
        self.assertEqual(r.evidence_metadata['classification'],'unsupported_modeling')


class Workers(unittest.TestCase):
    def test_mc_uses_conversion_and_return_semantics(self):
        p=problem('BOOL','INT',((False,0),(True,1)))
        p.specs=[__import__('stbench.schema',fromlist=['Spec']).Spec(sid='S1',text='convert',ltl='G(outputValue = TO_INT(inputValue))')]
        p.mc_inputs={'inputValue':[False,True]}
        src='FUNCTION_BLOCK FB VAR_INPUT inputValue:BOOL; END_VAR VAR_OUTPUT outputValue:INT; END_VAR outputValue:=TO_INT(inputValue); RETURN; outputValue:=99; END_FUNCTION_BLOCK'
        r=judge.evaluate(src,p,timeout_s=15)
        self.assertTrue(r.all_tests_passed);self.assertTrue(r.specs_all_hold,r.mc_error)
        self.assertEqual(r.evidence_metadata['r5_model_check']['requested_depth'],2)

    def test_only_mc_domain_overflow_does_not_become_counterexample(self):
        p=problem();p.mc_inputs={'inputValue':[40000]}
        from stbench.schema import Spec
        p.specs=[Spec(sid='S1',text='positive',ltl='G(outputValue >= 0)')]
        r=judge.evaluate(code(),p,timeout_s=15)
        self.assertTrue(r.all_tests_passed);self.assertIn('Unsupported modeling',r.mc_error)
        self.assertEqual(r.mc_specs_violated,0);self.assertEqual(r.mc_specs_inconclusive,1)

    def test_total_worker_deadline(self):
        before=time.monotonic();r=judge.evaluate(code(),problem(),timeout_s=.001)
        self.assertLess(time.monotonic()-before,2);self.assertIn('timeout',r.mc_error)

    def test_unmodeled_formula_is_isolated_from_good_property(self):
        from stbench.schema import Spec,VarDef,Direction
        p=problem();p.variables.append(VarDef(name='realInput',data_type='REAL',direction=Direction.INPUT))
        p.test_cases[0].inputs['realInput']=1.5
        p.mc_inputs={'inputValue':[3],'realInput':[1.5]}
        p.specs=[Spec(sid='good',text='positive',ltl='G(outputValue > 0)'),
                 Spec(sid='unmodeled',text='float',ltl='G(TO_INT(realInput) > 0)')]
        src='FUNCTION_BLOCK FB VAR_INPUT inputValue:DINT; realInput:REAL; END_VAR VAR_OUTPUT outputValue:INT; END_VAR outputValue:=TO_INT(inputValue); END_FUNCTION_BLOCK'
        r=judge.evaluate(src,p,timeout_s=15)
        self.assertTrue(r.all_tests_passed);self.assertFalse(r.mc_error)
        self.assertEqual((r.mc_specs_total,r.mc_specs_hold,r.mc_specs_inconclusive),(2,1,1))

    def test_unmodeled_scan_does_not_erase_confirmed_counterexample(self):
        from stbench.schema import Spec
        p=problem();p.mc_inputs={'inputValue':[3,40000]}
        p.specs=[Spec(sid='bad',text='zero',ltl='G(outputValue = 0)')]
        r=judge.evaluate(code(),p,timeout_s=15)
        self.assertTrue(r.all_tests_passed)
        self.assertEqual(r.mc_specs_violated,1);self.assertIn('Unsupported modeling',r.mc_error)

    def test_mixed_groups_still_all_counted(self):
        p=next(p for p in v.problems() if p.pid=='self-hard-04');q,src,_=v.adapt(p)
        r=judge.evaluate(src,q,model_check=False,timeout_s=15)
        self.assertEqual((r.tests_passed,r.tests_total),(18,18))
        self.assertEqual(r.evidence_metadata['group_counts'],{'single':5,'sequence:pump':13})

    def test_profile_mismatch_rejected(self):
        class Backend:name='openplc'
        with self.assertRaises(ValueError):judge.evaluate(code(),problem(),profile='codesys',backends=(Backend(),))

    def test_preserved_parent_hashes(self):
        v.verify_parent();v.r4.r3.r2.r1.verify_engine()


if __name__=='__main__':unittest.main()

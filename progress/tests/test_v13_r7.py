"""Parser semantics, negative controls and isolation of the new formula layer."""
import copy
import itertools
from pathlib import Path
import sys
import unittest

REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO/'progress/v13_r7'))
import r7_revision as v
import r7_ltl as ltl
import r7_judge as judge
from r7_runtime import modelcheck
from conversions import runtime
from stbench import ltl as legacy
from stbench.schema import Problem


def problem(specs=None,body='actual := request;'):
    p=Problem.from_dict(dict(pid='r7-control',source='selfmade',difficulty='easy',title='control',requirements='fixture',
        case_mode='single',variables=[dict(name='request',data_type='BOOL',direction='input'),
            dict(name='actual',data_type='BOOL',direction='output')],
        test_cases=[dict(tc_id='one',inputs=dict(request=False),expected=dict(actual=False))],
        specs=[dict(sid=sid,text=sid,ltl=formula,verified_by='bounded_checker') for sid,formula in (specs or [])],
        mc_inputs=dict(request=[False,True]),mc_max_depth=6,mc_max_traces=500,mc_max_seconds=2))
    source='FUNCTION_BLOCK FB VAR_INPUT request:BOOL; END_VAR VAR_OUTPUT actual:BOOL; END_VAR '+body+' END_FUNCTION_BLOCK'
    return p,source


def atom(text,snap,previous=None):
    return runtime('codesys').modelcheck._atom_evaluator({'request':'BOOL','actual':'BOOL','count':'INT'},{})(text,snap,previous)
atom._accepts_prev=True


class FormulaRevision(unittest.TestCase):
    def test_word_and_symbolic_negation_agree_on_all_edges(self):
        for bits in itertools.product((False,True),repeat=4):
            trace=[dict(request=x,actual=False) for x in bits]
            a=ltl.evaluate('G(NOT rising(request) -> NOT actual)',trace,atom)
            b=ltl.evaluate('G(!rising(request) -> !actual)',trace,atom)
            self.assertEqual((a.holds,a.inconclusive),(b.holds,b.inconclusive))

    def test_not_rising_can_find_real_violation(self):
        trace=[dict(request=False,actual=False),dict(request=False,actual=True)]
        verdict=ltl.evaluate('G(NOT rising(request) -> NOT actual)',trace,atom)
        self.assertFalse(verdict.holds);self.assertEqual(verdict.counterexample_at,2)

    def test_five_nested_previous_scans(self):
        trace=[dict(actual=i<5) for i in range(7)]
        formula='G(actual <-> NOT prev(prev(prev(prev(prev(TRUE))))))'
        self.assertTrue(ltl.evaluate(formula,trace,atom).holds)
        bad=copy.deepcopy(trace);bad[4]['actual']=False
        self.assertEqual(ltl.evaluate(formula,bad,atom).counterexample_at,5)

    def test_numeric_left_comparison_matches_reversed_form(self):
        for values in itertools.product((0,1,2),repeat=3):
            trace=[dict(count=x) for x in values]
            a=ltl.evaluate('G(0 < count <-> count > 0)',trace,atom)
            self.assertTrue(a.holds)

    def test_numeric_previous_uses_declared_initial_value(self):
        verdict=ltl.evaluate('G(0 < prev(count))',[dict(count=4)],atom,init_snapshot=dict(count=7))
        self.assertTrue(verdict.holds)

    def test_numeric_false_comparison_rejects(self):
        self.assertFalse(ltl.evaluate('G(0 < count)',[dict(count=0)],atom).holds)

    def test_negated_equivalence_preserves_toggle_logic(self):
        formula='G(actual <-> NOT (rising(request) <-> prev(actual)))'
        trace=[dict(request=True,actual=True),dict(request=False,actual=True),dict(request=True,actual=False)]
        self.assertTrue(ltl.evaluate(formula,trace,atom).holds)
        trace[2]['actual']=True
        self.assertFalse(ltl.evaluate(formula,trace,atom).holds)

    def test_formula_names_see_inside_word_negation(self):
        self.assertEqual(ltl.formula_names('G(NOT rising(request) -> actual = FALSE)'),{'request','actual'})

    def test_old_formula_module_is_not_patched(self):
        before=(legacy.parse,legacy.evaluate,legacy._Parser.p_unary,legacy._Parser.p_atom)
        ltl.parse('G(NOT rising(request))');modelcheck('codesys')
        self.assertEqual(before,(legacy.parse,legacy.evaluate,legacy._Parser.p_unary,legacy._Parser.p_atom))
        self.assertNotEqual(legacy.parse('G(NOT rising(request))'),ltl.parse('G(NOT rising(request))'))

    def test_old_runtime_module_is_not_patched(self):
        old=runtime('codesys').modelcheck
        before=(old.parse,old.evaluate,old.Interpreter,old.check)
        new=modelcheck('codesys')
        self.assertIsNot(new,old)
        self.assertEqual(before,(old.parse,old.evaluate,old.Interpreter,old.check))

    def test_model_checker_uses_new_parser_and_reports_violation(self):
        p,source=problem([('bad','G(NOT rising(request) -> NOT actual)')],body='actual := TRUE;')
        result=judge.evaluate(source,p,verification_after_tests=False,timeout_s=5)
        self.assertTrue(result.mc_executed)
        self.assertEqual(result.mc_specs_violated,1,result.mc_error)

    def test_model_checker_history_window_reaches_fifth_scan(self):
        mc=modelcheck('codesys')
        source='FUNCTION_BLOCK FB VAR_OUTPUT actual:BOOL; END_VAR VAR count:INT; END_VAR count:=count+1; actual:=count<=4; END_FUNCTION_BLOCK'
        formula='G(actual <-> NOT prev(prev(prev(prev(prev(TRUE))))))'
        report=mc.check(source,[('timing',formula)],mc.InputSpace({}),max_depth=6,max_traces=100,max_seconds=2,
            observable_names={'actual'})
        self.assertEqual(report.specs[0].ce_at,5)

    def test_unbound_property_does_not_erase_good_or_bad_property(self):
        mc=modelcheck('codesys');p,source=problem()
        report=mc.check(source,[('good','G(actual = request)'),('bad','G(NOT actual)'),('missing','G(NOT prev(ghost))')],
            mc.InputSpace(dict(request=[False,True])),max_depth=3,max_traces=100,max_seconds=2,observable_names={'request','actual'})
        rows={r.spec_id:r for r in report.specs}
        self.assertTrue(rows['good'].holds)
        self.assertTrue(rows['bad'].contradicting)
        self.assertTrue(rows['missing'].inconclusive)

    def test_unknown_function_stays_unresolved(self):
        mc=modelcheck('codesys');p,source=problem()
        report=mc.check(source,[('unknown','G(NOT UNKNOWN(request))'),('good','G(actual = request)')],
            mc.InputSpace(dict(request=[False,True])),max_depth=3,max_traces=100,max_seconds=2)
        rows={r.spec_id:r for r in report.specs}
        self.assertTrue(rows['unknown'].inconclusive)
        self.assertTrue(rows['good'].holds)

    def test_future_boundary_remains_inconclusive(self):
        out=ltl.evaluate('G(X(actual))',[dict(actual=True)],atom)
        self.assertTrue(out.inconclusive)

    def test_tests_first_skips_formal_on_functional_failure(self):
        p,source=problem([('one','G(NOT rising(request))')],body='actual:=TRUE;')
        result=judge.evaluate(source,p,verification_after_tests=True,timeout_s=5)
        self.assertFalse(result.all_tests_passed);self.assertFalse(result.mc_executed)

    def test_no_model_check_requested_skips_worker(self):
        p,source=problem([('one','G(actual = request)')])
        result=judge.evaluate(source,p,model_check=False,timeout_s=5)
        self.assertTrue(result.all_tests_passed);self.assertFalse(result.mc_executed)

    def test_total_deadline_is_preserved(self):
        p,source=problem([('one','G(actual = request)')])
        result=judge.evaluate(source,p,timeout_s=0)
        self.assertFalse(result.mc_executed)
        self.assertEqual(result.evidence_metadata['classification'],'tool_error')

    def test_all_functional_cases_and_reference_bytes_unchanged(self):
        old={p.pid:p for p in v.r6.problems()}
        for p in v.problems():
            self.assertEqual([c.to_dict() for c in p.test_cases],[c.to_dict() for c in old[p.pid].test_cases])
            self.assertEqual(v.reference(p),v.r6.reference(old[p.pid]))

    def test_conversion_model_and_source_hash_preserved(self):
        p,source=problem()
        result=judge.local_tests(source,p)
        self.assertEqual(result.evidence_metadata['candidate_source_sha256'],v.digest(source.encode()))
        self.assertFalse(result.evidence_metadata['candidate_text_rewritten'])

    def test_model_checker_keeps_generic_conversion_and_return(self):
        mc=modelcheck('codesys')
        source='FUNCTION_BLOCK FB VAR_INPUT value:DINT; END_VAR VAR_OUTPUT actual:INT; END_VAR IF value>0 THEN actual:=TO_INT(value); RETURN; END_IF; actual:=0; END_FUNCTION_BLOCK'
        report=mc.check(source,[('conversion','G(value > 0 -> actual = value)')],mc.InputSpace(dict(value=[0,1,2])),
            max_depth=3,max_traces=100,max_seconds=2)
        self.assertTrue(report.all_hold,report.error)

    def test_unmodeled_conversion_does_not_erase_counterexample(self):
        mc=modelcheck('codesys')
        source='FUNCTION_BLOCK FB VAR_INPUT value:DINT; END_VAR VAR_OUTPUT actual:INT; END_VAR actual:=TO_INT(value); END_FUNCTION_BLOCK'
        report=mc.check(source,[('bad','G(actual = 0)')],mc.InputSpace(dict(value=[1,40000])),
            max_depth=2,max_traces=100,max_seconds=2)
        self.assertIn('Unsupported modeling',report.error)
        self.assertTrue(report.specs[0].contradicting)


if __name__=='__main__':unittest.main()

"""Binding domains must cover every binding without allowing mid-run rebinding."""
import unittest
from stbench.cli import problems,reference
from stbench.evaluation import evaluate
from stbench.modelcheck import InputSpace,check
from stbench.portability import adapt
from stbench.schema import Problem

COUNTER='''FUNCTION_BLOCK FB
VAR_INPUT capacity:INT; END_VAR
VAR_OUTPUT count:INT; END_VAR
IF count < capacity THEN count:=count+1; END_IF;
END_FUNCTION_BLOCK'''


class FixedBindings(unittest.TestCase):
    def test_dynamic_shrink_fails_but_both_fixed_bindings_are_checked(self):
        args=dict(max_depth=5,max_traces=500,max_seconds=2)
        specs={'bound':'G(count <= capacity)'}
        dynamic=check(COUNTER,specs,InputSpace({'capacity':[2,4]}),**args)
        self.assertTrue(dynamic.contradictions)
        fixed=check(COUNTER,specs,InputSpace({'capacity':[2,4]},('capacity',)),**args)
        self.assertTrue(fixed.all_hold,fixed.to_dict())
        self.assertEqual(fixed.fixed_input_domains,{'capacity':[2,4]})

    def test_equal_initial_memory_does_not_merge_different_bindings(self):
        code='''FUNCTION_BLOCK FB
VAR_INPUT capacity:INT; END_VAR
VAR_OUTPUT count:INT; END_VAR
VAR cycles:INT; END_VAR
cycles:=cycles+1;
IF cycles=2 AND capacity=4 THEN count:=5; ELSE count:=0; END_IF;
END_FUNCTION_BLOCK'''
        result=check(code,{'bound':'G(count <= capacity)'},InputSpace({'capacity':[2,4]},('capacity',)),
            max_depth=2,max_traces=100,max_seconds=2)
        self.assertTrue(result.contradictions)
        self.assertEqual({s['capacity'] for s in result.contradictions[0].counterexample},{4})

    def test_unknown_fixed_domain_is_an_error_not_a_vacuous_pass(self):
        result=check(COUNTER,{'bound':'G(count <= capacity)'},InputSpace({'capacity':[2,4]},('missing',)),
            max_depth=2,max_traces=100,max_seconds=2)
        self.assertIn('missing',result.error)
        self.assertFalse(result.all_hold)

    def test_problem_roundtrip_worker_and_evidence_preserve_binding_contract(self):
        p=Problem.from_dict(dict(pid='fixed-counter',source='selfmade',title='counter',difficulty='easy',
            requirements='bound',variables=[dict(name='capacity',data_type='INT',direction='input'),
                dict(name='count',data_type='INT',direction='output')],
            test_cases=[dict(tc_id='first',inputs={'capacity':2},expected={'count':1})],
            specs=[dict(sid='bound',text='bound',ltl='G(count <= capacity)')],
            mc_inputs={'capacity':[2,4]},mc_fixed_inputs=['capacity'],mc_max_depth=5,mc_max_traces=500))
        self.assertEqual(Problem.from_dict(p.to_dict()).mc_fixed_inputs,['capacity'])
        result=evaluate(COUNTER,p,timeout_s=5)
        self.assertTrue(result.specs_all_hold,result.to_dict())
        self.assertEqual(result.mc_fixed_input_domains,{'capacity':[2,4]})
        self.assertEqual(result.evidence_metadata['mc_fixed_input_domains'],{'capacity':[2,4]})

    def test_fifo_adaptation_keeps_raw_data_and_enumerates_both_original_capacities(self):
        p=next(p for p in problems() if p.pid=='public-hard-04');before=p.to_dict()
        q,_,mapping=adapt(p,reference(p),'codesys')
        self.assertEqual(p.to_dict(),before)
        self.assertEqual(q.mc_fixed_inputs,['capacity'])
        self.assertEqual(q.mc_inputs['capacity'],[2,4])
        self.assertEqual([c.expected for c in q.test_cases],[c.expected for c in p.test_cases])
        self.assertEqual(mapping['profile'],'portable-frame-v5')


if __name__=='__main__':unittest.main()

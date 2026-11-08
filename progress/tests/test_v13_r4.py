"""Behavioral checks for review-2 contracts, grouping and property isolation."""
import copy
from pathlib import Path
import sys
import time
import unittest

REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO/'progress/v13_r4'))
import r4_revision as v
import r4_judge as judge
from stbench.schema import Problem
from stbench.st.driver import _collect_domains

SIMPLE='''FUNCTION_BLOCK FB
VAR_INPUT x : BOOL; END_VAR
VAR_OUTPUT y : BOOL; END_VAR
y := x;
END_FUNCTION_BLOCK'''


class Review2Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tasks={p.pid:p for p in v.problems()};cls.mc=v.load_modelcheck()

    def test_batch_priority_and_timeout_boundaries(self):
        p,c,_=v.adapt(self.tasks['self-hard-02']);r=judge.local_tests(c,p)
        self.assertTrue(r.all_tests_passed)
        rows={x.tc_id:x for x in r.cases}
        self.assertEqual(rows['b11'].actual,dict(phase=9,elapsed=3,timeout=True))
        self.assertEqual(rows['b12'].actual['phase'],9)
        self.assertEqual(rows['b15'].actual['phase'],3)

    def test_old_batch_reference_is_rejected(self):
        p,_,_=v.adapt(self.tasks['self-hard-02'])
        old=v.r3.reference(self.tasks['self-hard-02'])
        r=judge.local_tests(old,p)
        self.assertFalse(r.all_tests_passed)
        self.assertIn('b9',[x.tc_id for x in r.cases if not x.passed])

    def test_pump_both_test_groups_are_counted(self):
        p,c,_=v.adapt(self.tasks['self-hard-04']);r=judge.local_tests(c,p)
        self.assertEqual((r.tests_passed,r.tests_total),(18,18))
        self.assertEqual(r.evidence_metadata['group_counts'],{'single':5,'sequence:pump':13})

    def test_pump_50_is_strict(self):
        p,c,_=v.adapt(self.tasks['self-hard-04'])
        r=judge.local_tests(c.replace('> 50','>= 50'),p)
        self.assertIn('p9',[x.tc_id for x in r.cases if not x.passed])

    def test_pump_stable_tie_order(self):
        p,c,_=v.adapt(self.tasks['self-hard-04']);r=judge.local_tests(c,p)
        rows={x.tc_id:x for x in r.cases}
        self.assertEqual((rows['p16'].actual['leadPump'],rows['p17'].actual['leadPump']),(1,1))

    def test_pump_no_request_and_reset(self):
        p,c,_=v.adapt(self.tasks['self-hard-04']);r=judge.local_tests(c,p)
        rows={x.tc_id:x for x in r.cases}
        self.assertEqual([rows[x].actual['leadPump'] for x in ('p12','p15','p16')],[2,0,1])

    def test_heater_independent_traces(self):
        p,c,_=v.adapt(self.tasks['public-medium-04']);r=judge.local_tests(c,p)
        self.assertEqual((r.tests_passed,r.tests_total),(44,44))
        rows={x.tc_id:x.actual for x in r.cases}
        self.assertTrue(rows['boundary-low-8']['HeaterOutput'])
        for name in ('boundary-equal-8','boundary-fault-8'):
            self.assertFalse(rows[name]['HeaterOutput']);self.assertFalse(rows[name]['OverheatProtection'])

    def test_heater_late_protection_is_rejected(self):
        p,c,_=v.adapt(self.tasks['public-medium-04'])
        r=judge.local_tests(c.replace('onRun >= 5','onRun > 5'),p)
        self.assertIn('boundary-low-5',[x.tc_id for x in r.cases if not x.passed])

    def test_pi_existing_contract_and_input_domains(self):
        p,c,_=v.adapt(self.tasks['self-hard-07']);r=judge.local_tests(c,p)
        self.assertTrue(r.all_tests_passed)
        self.assertIn('不得再次折算',p.requirements)
        d=_collect_domains(p)
        for name,hi in [('manualFlowSP',50),('manualValve',100)]:
            values=next(values for key,values in d.items() if key.lower()==name.lower())
            self.assertTrue(all(0<=x<=hi for x in values))

    def test_incomplete_later_group_rejected_before_evaluation(self):
        p,c,_=v.adapt(self.tasks['self-hard-04']);p.test_cases[-1].expected.pop('leadPump')
        r=judge.local_tests(c,p)
        self.assertFalse(r.evidence_metadata['candidate_evaluated'])
        self.assertFalse(r.evidence_metadata['test_contract_valid'])

    def test_missing_name_does_not_erase_sibling(self):
        r=self.mc.check(SIMPLE,{'bad':'G(missing = 1)','good':'G(y = x)'},self.mc.InputSpace({'x':[False,True]}),max_depth=3)
        s={x.spec_id:x for x in r.specs}
        self.assertFalse(r.error);self.assertTrue(s['bad'].inconclusive);self.assertTrue(s['good'].holds)

    def test_missing_dead_branch_cannot_pass_vacuously(self):
        r=self.mc.check(SIMPLE,{'bad':'G(FALSE -> missing = 1)'},self.mc.InputSpace({'x':[False]}),max_depth=2)
        self.assertTrue(r.specs[0].inconclusive);self.assertFalse(r.specs[0].holds)

    def test_runtime_property_exception_is_isolated(self):
        r=self.mc.check(SIMPLE,{'bad':'G(UNKNOWN_FN(x))','good':'G(y = x)'},self.mc.InputSpace({'x':[False,True]}),max_depth=3)
        s={x.spec_id:x for x in r.specs}
        self.assertFalse(r.error);self.assertIn('Property evaluation error',s['bad'].reason)
        self.assertTrue(s['good'].holds)

    def test_first_layer_truncation_is_honest(self):
        r=self.mc.check(SIMPLE,{'s':'G(y = x)'},self.mc.InputSpace({'x':[False,True]}),max_depth=8,max_traces=1)
        self.assertTrue(r.truncated);self.assertEqual(r.max_depth,1);self.assertEqual(r.complete_depth,0)
        self.assertEqual(r.requested_depth,8);self.assertFalse(r.all_hold)

    def test_complete_depth_does_not_inflate_partial_layer(self):
        r=self.mc.check(SIMPLE,{'s':'G(y = x)'},self.mc.InputSpace({'x':[False,True]}),max_depth=8,max_traces=3)
        self.assertTrue(r.truncated);self.assertEqual(r.max_depth,2);self.assertEqual(r.complete_depth,1)

    def test_worker_preserves_depth_metadata(self):
        p,_,_=v.adapt(self.tasks['self-hard-02']);p.mc_inputs={'startBtn':[False],'abortBtn':[False],'maxDuration':[1],'pv':[20.],'setpoint':[100.]}
        p.mc_max_depth=2;p.mc_max_seconds=1
        r=judge.evaluate(v.reference(p),p,timeout_s=15)
        self.assertTrue(r.all_tests_passed);self.assertTrue(r.mc_executed)
        self.assertEqual(r.evidence_metadata['r4_model_check']['requested_depth'],2)
        self.assertEqual(r.mc_specs_total,5)

    def test_worker_has_total_deadline(self):
        p,c,_=v.adapt(self.tasks['self-hard-02']);t=time.monotonic()
        r=judge.evaluate(c,p,timeout_s=.001)
        self.assertLess(time.monotonic()-t,2);self.assertIn('timeout',r.mc_error)

    def test_sources_and_domains_not_modified(self):
        p,c,_=v.adapt(self.tasks['self-hard-04']);before=copy.deepcopy(p.to_dict())
        judge.local_tests(c,p)
        self.assertEqual(p.to_dict(),before)
        self.assertTrue(all(not p.mc_inputs for p in self.tasks.values()))

    def test_fixed_parent_integrity(self):
        v.verify_parent();v.r3.r2.r1.verify_engine()


if __name__=='__main__':unittest.main()

"""Regressions for the reviewed contracts, not score-fitting to model answers."""
import copy
import json
from pathlib import Path
import sys
import unittest

REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO/'progress/v13_r6'))
import r6_revision as v
import r6_judge as judge
from stbench.schema import Problem


class ReviewNovember10(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.problems={p.pid:p for p in v.problems()}
        cls.old={p.pid:p for p in v.r5.problems()}
        cls.audit=json.loads((v.ROOT/'adoption.json').read_text('utf-8'))

    def test_all_old_assertions_and_initial_states_retained(self):
        for pid,old in self.old.items():
            previous=v.r5.adapt(old)[0]
            self.assertEqual([c.to_dict() for c in previous.test_cases],
                [c.to_dict() for c in self.problems[pid].test_cases[:len(previous.test_cases)]],pid)

    def test_parent_and_raw_source_integrity(self):
        v.verify_parent()
        manifest=json.loads((v.ROOT/'upstream_manifest.json').read_text('utf-8'))
        for name,expected in manifest['files'].items():
            self.assertEqual(v.digest((v.ROOT/'upstream'/name).read_bytes()),expected,name)

    def test_old_tank_reference_rejected_by_new_danger_reset_cases(self):
        p=self.problems['self-easy-02'];old=v.r5.adapt(self.old[p.pid])[1]
        r=judge.local_tests(old,p)
        self.assertFalse(r.all_tests_passed)
        self.assertIn('peer-s10',[c.tc_id for c in r.cases if not c.passed])

    def test_tank_danger_reset_and_release_need_new_edge(self):
        p=copy.deepcopy(self.problems['self-easy-02'])
        rows=[]
        for i,(level,reset,high) in enumerate([(90,True,True),(50,True,True),(50,False,True),(50,True,False)]):
            rows.append(dict(tc_id=str(i),mode='sequence',inputs=dict(tankLevel=level,resetBtn=reset,inletPermit=True),
                expected=dict(alarmHigh=high,alarmLow=False,pumpRun=not high,outletValveOpen=True),expect_full=True))
        d=p.to_dict();d.update(case_mode='sequence',test_cases=rows)
        result=judge.local_tests(v.reference(p),Problem.from_dict(d))
        self.assertTrue(result.all_tests_passed,result.failure_summary)

    def test_old_recipe_reference_rejected_for_stale_id(self):
        p=self.problems['self-medium-01'];result=judge.local_tests(v.r5.adapt(self.old[p.pid])[1],p)
        self.assertFalse(result.all_tests_passed)
        self.assertIn('peer-hold-5',[c.tc_id for c in result.cases if not c.passed])

    def test_old_fill_reference_rejected_at_int_limit(self):
        p=self.problems['self-medium-04'];result=judge.local_tests(v.r5.adapt(self.old[p.pid])[1],p)
        self.assertFalse(result.all_tests_passed)
        self.assertIn('peer-fill-limit-4',[c.tc_id for c in result.cases if not c.passed])

    def test_fill_saturation_still_completes_and_resets(self):
        p=copy.deepcopy(self.problems['self-medium-04'])
        p.test_cases=[c for c in p.test_cases if c.mode=='sequence:peer:counter-limit']
        result=judge.local_tests(v.reference(p),p)
        self.assertEqual(result.tests_total,7)
        self.assertTrue(result.all_tests_passed,result.failure_summary)

    def test_gate_conflicting_contract_not_installed(self):
        p=self.problems['self-medium-03']
        self.assertEqual(v.reference(p),v.r5.adapt(self.old[p.pid])[1])
        self.assertFalse(any(c.tc_id.startswith('peer-') for c in p.test_cases))
        row=next(x for x in self.audit['tasks'] if x['pid']==p.pid)
        self.assertTrue(all(g['decision']=='defer' for g in row['groups']))

    def test_pump_preserves_lag_across_two_to_three_demand(self):
        p=copy.deepcopy(self.problems['self-hard-04']);d=p.to_dict()
        d['test_cases']=[dict(tc_id='initial',mode='sequence',inputs=dict(demand=2,rotated=False,runHours=[160,109,300,400,500]),
            expected=dict(leadPump=2,lagPump=1,runningCount=2),expect_full=True),
            dict(tc_id='increase',mode='sequence',inputs=dict(demand=3,rotated=False,runHours=[300,250,120,400,500]),
            expected=dict(leadPump=2,lagPump=1,runningCount=3),expect_full=True)]
        result=judge.local_tests(v.reference(p),Problem.from_dict(d))
        self.assertTrue(result.all_tests_passed,result.failure_summary)
        row=next(x for x in self.audit['tasks'] if x['pid']==p.pid)
        seq=next(g for g in row['groups'] if g['group']=='sequence:peer:seq')
        self.assertEqual(seq['count'],12);self.assertEqual(seq['decision'],'defer')

    def test_fifo_prefix_does_not_weaken_visible_tail_assertions(self):
        p=self.problems['self-hard-03']
        peer=[c for c in p.test_cases if c.tc_id.startswith('peer-')]
        self.assertEqual(len(peer),45)
        assertions=[c for c in peer if 'fifo' in c.expected]
        self.assertGreater(len(assertions),30)
        for c in assertions:
            self.assertIsInstance(c.expected['fifo'],list)
            self.assertEqual(len(c.expected['fifo']),8)
            self.assertTrue(all(x==0 for x in c.expected['fifo'][c.expected['count']:]))
        mutant=v.reference(p).replace('END_FUNCTION_BLOCK','fifo[8] := 123;\nEND_FUNCTION_BLOCK')
        self.assertFalse(judge.local_tests(mutant,p).all_tests_passed)

    def test_fixed_capacity_not_physical_padding_in_new_fifo_formulas(self):
        p=self.problems['public-hard-04']
        self.assertEqual([x.name.lower() for x in p.variables].count('capacity'),1)
        for s in p.specs:
            if s.sid.startswith('N10-'):
                self.assertNotIn('UPPER_BOUND',s.ltl.upper())
        result=judge.local_tests(v.reference(p),p)
        self.assertTrue(result.all_tests_passed,result.failure_summary)

    def test_no_double_portability_conversion(self):
        p=self.problems['self-hard-07'];q,source,_=v.adapt(p)
        self.assertEqual([x.to_dict() for x in p.variables],[x.to_dict() for x in q.variables])
        self.assertEqual([x.to_dict() for x in p.test_cases],[x.to_dict() for x in q.test_cases])
        self.assertIn('scanSeconds',[x.name for x in q.variables])
        self.assertEqual(source,v.reference(p))

    def test_duplicate_independent_ipv4_cases_not_double_counted(self):
        self.assertEqual(len(self.problems['public-medium-08'].test_cases),16)

    def test_human_approval_not_inferred_from_sender_certificates(self):
        for p in self.problems.values():
            record=p.provenance['human_process_review']
            self.assertEqual(record['reviewer'],'刘晏铭')
            self.assertFalse(record['approved'])

    def test_execution_model_and_data_identity_are_separate(self):
        p=self.problems['public-easy-03'];source=v.reference(p)
        result=judge.local_tests(source,p)
        self.assertEqual(result.evidence_metadata['data_version'],v.VERSION)
        self.assertEqual(result.evidence_metadata['execution_judge'],v.JUDGE_VERSION)
        self.assertFalse(result.evidence_metadata['candidate_text_rewritten'])
        self.assertEqual(result.evidence_metadata['candidate_source_sha256'],v.digest(source.encode()))


if __name__=='__main__':unittest.main()

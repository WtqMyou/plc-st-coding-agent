"""Returned contract decisions and preservation of unrelated experiments."""
import copy
import json
from pathlib import Path
import sys
import unittest

REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO/'progress/v13_r8'))
import r8_revision as v
import r8_judge as judge
from stbench.schema import Problem


class ReturnedReview(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data={p.pid:p for p in v.problems()}
        cls.old={p.pid:p for p in v.r7.problems()}

    def execute(self,pid,steps):
        p=self.data[pid];d=p.to_dict();d['case_mode']='sequence'
        d['test_cases']=[dict(tc_id=str(i),mode='sequence',inputs=inputs,expected=expected,init=init)
            for i,(inputs,expected,init) in enumerate(steps)]
        result=judge.local_tests(v.reference(p),Problem.from_dict(d))
        self.assertTrue(result.compiles and result.all_tests_passed,result.failure_summary)
        return result

    def test_unchanged_32_functional_contracts_and_sources(self):
        unchanged=set(self.data)-v.CONTRACT_CHANGED
        self.assertEqual(len(unchanged),32)
        self.assertEqual(sum(len(self.data[p].test_cases) for p in unchanged),1113)
        for pid in unchanged:
            self.assertEqual([c.to_dict() for c in self.data[pid].test_cases],[c.to_dict() for c in self.old[pid].test_cases],pid)
            self.assertEqual(v.reference(self.data[pid]),v.r7.reference(self.old[pid]),pid)

    def test_parent_snapshots_still_intact(self):
        v.verify_parent();v.r7.verify_parent()

    def test_r7_additions_not_dropped_by_older_return_base(self):
        self.assertIn('N10-S7',{s.sid for s in self.data['public-medium-04'].specs})
        self.assertIn('N10-S17',{s.sid for s in self.data['self-hard-06'].specs})

    def test_millisecond_interface_does_not_reuse_old_time_names(self):
        names={x.name for x in self.data['public-easy-04'].variables}
        self.assertIn('CycleMs',names);self.assertIn('DebounceMs',names)
        self.assertNotIn('CycleTime',names);self.assertNotIn('DebounceTime',names)
        self.assertIn('CycleTime',{x.name for x in self.old['public-easy-04'].variables})

    def test_exact_millisecond_threshold_starts_on_fifth_scan(self):
        steps=[]
        for i in range(5):
            steps.append((dict(VISCOSITY_OK=True,PASTE_E_STOP_NC=True,DebounceMs=500,CycleMs=100),
                dict(VFD_RUN=i==4,PUMP_RUNTIME_ACC=100 if i==4 else 0,PUMP_MAINT_DUE=False),{}))
        self.execute('public-easy-04',steps)

    def test_500_hour_threshold_uses_milliseconds(self):
        self.execute('public-easy-04',[(dict(VISCOSITY_OK=True,PASTE_E_STOP_NC=True,DebounceMs=1,CycleMs=3600000),
            dict(VFD_RUN=True,PUMP_RUNTIME_ACC=1800000000,PUMP_MAINT_DUE=True),dict(PUMP_RUNTIME_ACC=1796400000))])

    def test_millisecond_emergency_stop_discards_partial_debounce(self):
        steps=[]
        for safe,on,acc in [(True,False,0),(False,False,0),(True,False,0),(True,True,200)]:
            steps.append((dict(VISCOSITY_OK=True,PASTE_E_STOP_NC=safe,DebounceMs=300,CycleMs=200),
                dict(VFD_RUN=on,PUMP_RUNTIME_ACC=acc,PUMP_MAINT_DUE=False),{}))
        self.execute('public-easy-04',steps)

    def test_pump_reselects_lag_when_demand_increases(self):
        self.execute('self-hard-04',[
            (dict(demand=2,rotated=False,runHours=[160,109,300,400,500]),dict(leadPump=2,lagPump=1,runningCount=2),{}),
            (dict(demand=3,rotated=False,runHours=[300,250,120,400,500]),dict(leadPump=2,lagPump=3,runningCount=3),{})])

    def test_pump_compares_clipped_demand(self):
        self.execute('self-hard-04',[
            (dict(demand=7,rotated=False,runHours=[160,109,300,400,500]),dict(leadPump=2,lagPump=1,runningCount=5),{}),
            (dict(demand=9,rotated=False,runHours=[300,250,120,400,500]),dict(leadPump=2,lagPump=1,runningCount=5),{})])

    def test_pump_still_requires_strict_50_hour_difference(self):
        self.execute('self-hard-04',[
            (dict(demand=2,rotated=False,runHours=[0,100,300,400,500]),dict(leadPump=1,lagPump=2,runningCount=2),{}),
            (dict(demand=2,rotated=True,runHours=[150,100,300,400,500]),dict(leadPump=1,lagPump=2,runningCount=2),{}),
            (dict(demand=2,rotated=True,runHours=[151,100,300,400,500]),dict(leadPump=2,lagPump=1,runningCount=2),{})])

    def test_gate_faults_on_first_obstacle_and_does_not_auto_reverse(self):
        self.execute('self-medium-03',[
            (dict(openBtn=False,closeBtn=True,openLimit=False,closeLimit=False,obstacle=False),dict(motorUp=False,motorDown=True,errorFlag=False),{}),
            (dict(openBtn=False,closeBtn=False,openLimit=False,closeLimit=False,obstacle=True),dict(motorUp=False,motorDown=False,errorFlag=True),{}),
            (dict(openBtn=False,closeBtn=False,openLimit=False,closeLimit=False,obstacle=False),dict(motorUp=False,motorDown=False,errorFlag=True),{})])

    def test_gate_held_reset_does_not_clear_after_obstacle(self):
        steps=[]
        for obstacle,open_btn,close_btn,error in [(True,False,False,True),(True,True,True,True),(False,True,True,True),
                                                (False,False,False,True),(False,True,True,False)]:
            steps.append((dict(obstacle=obstacle,openBtn=open_btn,closeBtn=close_btn,openLimit=False,closeLimit=False),
                dict(motorUp=False,motorDown=False,errorFlag=error),{}))
        self.execute('self-medium-03',steps)

    def test_gate_obstacle_has_priority_over_limits_and_reset(self):
        self.execute('self-medium-03',[(dict(obstacle=True,openBtn=True,closeBtn=True,openLimit=True,closeLimit=True),
            dict(motorUp=False,motorDown=False,errorFlag=True),{})])

    def test_future_style_recipe_and_fill_properties_replaced(self):
        recipe=next(s.ltl for s in self.data['self-medium-01'].specs if s.sid=='S4')
        fill=next(s.ltl for s in self.data['self-medium-04'].specs if s.sid=='S2')
        self.assertNotIn('X(',recipe);self.assertNotIn('X(',fill)

    def test_signature_not_inferred_from_technical_replay(self):
        for p in self.data.values():
            if 'lym_return' in p.provenance:
                self.assertFalse(p.provenance['human_process_review']['approved'])
                self.assertEqual(p.provenance['human_process_review']['status'],'lym_revision_received')


if __name__=='__main__':unittest.main()

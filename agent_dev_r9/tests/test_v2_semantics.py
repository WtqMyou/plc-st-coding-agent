import copy
import hashlib
import json
import unittest
from pathlib import Path
from stbench.schema import Problem,TestCase
from stbench.evaluation import local_tests
from stbench.cli import problems,reference
from stbench.portability import adapt
from stbench.modelcheck import check,InputSpace
from stbench.live import validate_live_config
from stbench.providers.base import ProviderError

ROOT=Path(__file__).resolve().parents[1]

class Semantics(unittest.TestCase):
    def task(self,pid,cases):
        p=Problem.load(ROOT/"datasets"/"selfmade"/(pid+".json"))
        p.case_mode="sequence"
        p.test_cases=[TestCase.from_dict(c) for c in cases]
        return local_tests(reference(p),p)
    def test_reset_hold_does_not_retrigger_high_alarm_reset(self):
        cases=[dict(tc_id=str(i),inputs={"tankLevel":85.,"resetBtn":True},expected={"alarmHigh":i>0})
               for i in range(3)]
        self.assertTrue(self.task("self-easy-02",cases).all_tests_passed)
    def test_low_level_reset_cannot_open_outlet(self):
        self.assertTrue(self.task("self-easy-02",[dict(tc_id="safety",
            inputs={"tankLevel":15.,"resetBtn":True},expected={"outletValveOpen":False})]).all_tests_passed)
    def test_batch_held_start_does_not_reset_elapsed(self):
        cases=[dict(tc_id=str(i),inputs={"startBtn":True,"pv":20.},
                    const_inputs={"setpoint":100.,"maxDuration":10},
                    expected={"elapsed":i,"phase":1}) for i in range(3)]
        self.assertTrue(self.task("self-hard-02",cases).all_tests_passed)
    def test_fill_held_start_cannot_restart_after_reset(self):
        cases=[dict(tc_id=str(i),inputs={"startBtn":True,"resetBtn":i==1},
                    const_inputs={"targetVol":49.,"flowVol":10.},expected={"valveOpen":i==0})
               for i in range(3)]
        self.assertTrue(self.task("self-medium-04",cases).all_tests_passed)
    def test_unacknowledged_alarm_survives_condition_clear(self):
        cases=[dict(tc_id="on",inputs={"flowLow":True,"sensorOK":True},
                    expected={"alarmActive":True,"alarmAcked":False}),
               dict(tc_id="returned",inputs={"flowLow":False,"sensorOK":True},
                    expected={"alarmActive":True,"alarmAcked":True}),
               dict(tc_id="ack",inputs={"flowLow":False,"ackBtn":True,"sensorOK":True},
                    expected={"alarmActive":False,"alarmAcked":False})]
        self.assertTrue(self.task("self-hard-01",cases).all_tests_passed)
    def test_held_ack_does_not_ack_a_new_alarm(self):
        cases=[dict(tc_id=str(i),inputs={"flowLow":i>0,"ackBtn":True,"sensorOK":True},
                    expected={"alarmActive":i>0,"alarmAcked":False}) for i in range(3)]
        self.assertTrue(self.task("self-hard-01",cases).all_tests_passed)
    def test_held_load_does_not_change_recipe(self):
        cases=[]
        for i in range(3):
            recipe=[dict(recipeID=101+i,totalRatio=100.,temperature=100.)]+[
                dict(recipeID=0,totalRatio=0.,temperature=0.) for _ in range(7)]
            cases.append(dict(tc_id=str(i),inputs={"recipe":recipe,"loadCmd":True,"selSlot":1},
                              expected={"loadedID":101,"valid":True}))
        self.assertTrue(self.task("self-medium-01",cases).all_tests_passed)
    def test_all_portable_variants_preserve_original_output_assertions(self):
        total=0
        for p in problems():
            original_expected=[copy.deepcopy(c.expected) for c in p.test_cases]
            q,src,mapping=adapt(p,reference(p),"openplc")
            self.assertEqual(original_expected,[c.expected for c in q.test_cases])
            r=local_tests(src,q)
            self.assertTrue(r.compiles,(p.pid,r.compile_errors))
            self.assertTrue(r.all_tests_passed,(p.pid,r.failure_summary))
            total+=r.tests_passed
        self.assertEqual(total,435)
    def test_trace_budget_is_not_passed_verification(self):
        src="FUNCTION_BLOCK FB VAR_INPUT a:BOOL; END_VAR VAR_OUTPUT b:BOOL; END_VAR b:=a; END_FUNCTION_BLOCK"
        r=check(src,{"s":"G(b = a)"},InputSpace({"a":[True,False]}),max_traces=2,max_depth=8)
        self.assertTrue(r.truncated)
    def test_nested_next_finds_third_scan_violation(self):
        src="FUNCTION_BLOCK FB VAR_INPUT a:BOOL; END_VAR VAR_OUTPUT b:BOOL; END_VAR VAR count:INT; END_VAR b:=count<2; count:=count+1; END_FUNCTION_BLOCK"
        r=check(src,{"s":"G(X(X(b)))"},InputSpace({"a":[False]}),max_traces=20,max_depth=4)
        self.assertTrue(r.contradictions)
    def test_no_unselected_model_or_missing_budget(self):
        template=json.loads((ROOT/"config.example.json").read_text(encoding="utf-8"))
        self.assertEqual(template["models"],[])
        self.assertIsNone(template["budget_cny"])
        with self.assertRaises(ProviderError):validate_live_config(template)
    def test_all_original_test_cases_unchanged(self):
        manifest=json.loads((ROOT/"evidence"/"original_input_manifest.json").read_text(encoding="utf-8"))
        expected={r["pid"]:r["test_cases_sha256"] for r in manifest["entries"]}
        self.assertEqual(len(expected),30)
        for p in problems():
            if p.pid not in expected:continue  # The five v1.2 additions have a separate upstream hash guard.
            raw=json.loads((ROOT/"datasets"/p.source/(p.pid+".json")).read_text(encoding="utf-8"))
            digest=hashlib.sha256(json.dumps(raw["test_cases"],sort_keys=True,ensure_ascii=False).encode()).hexdigest()
            self.assertEqual(digest,expected[p.pid])

if __name__=="__main__":
    unittest.main()

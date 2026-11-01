import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from stbench.schema import Problem
from stbench.evaluation import local_tests, evaluate, feedback_for_agent, verification_status
from stbench.st.driver import StageResult, CaseResult, verify_sequence
from stbench.harness.runner import Solver, solve_problem, summarize
from stbench.harness.prompts import build_task_prompt
from stbench.providers.mock import MockProvider
from stbench.providers.openai_compat import OpenAICompatProvider
from stbench.providers.base import ProviderError
from stbench.live import validate_live_config, Budget
from stbench.modelcheck import InputSpace, check
from stbench.platforms import CodesysBackend

ROOT=Path(__file__).resolve().parents[1]
CODE="FUNCTION_BLOCK FB\nVAR_INPUT a:BOOL; END_VAR\nVAR_OUTPUT b:BOOL; END_VAR\nb:=a;\nEND_FUNCTION_BLOCK"

def problem():
    return Problem.from_dict(dict(pid="supplement",source="selfmade",difficulty="easy",title="fixture",
        requirements="b equals a",variables=[dict(name="a",data_type="BOOL",direction="input"),
        dict(name="b",data_type="BOOL",direction="output")],case_mode="sequence",
        test_cases=[dict(tc_id="a",inputs={"a":True},expected={"b":True}),
                    dict(tc_id="b",inputs={"a":False},expected={"b":False})],
        specs=[dict(sid="S1",text="b matches a",ltl="G(b = a)",kind="safety",verified_by="plcverif")],
        mc_max_depth=2,mc_max_traces=32,mc_max_seconds=2))

class Core(unittest.TestCase):
    def test_mc_config_roundtrip(self):
        p=problem();p.mc_inputs={"a":[True]};q=Problem.from_dict(p.to_dict())
        self.assertEqual((q.mc_max_depth,q.mc_max_traces,q.mc_max_seconds,q.mc_inputs),(2,32,2,{"a":[True]}))
    def test_sequence_executes_ltl_and_finds_counterexample(self):
        p=problem();p.specs[0].ltl="G(NOT b)"
        r=verify_sequence(CODE,p,model_check=True)
        self.assertTrue(r.all_tests_passed)
        self.assertEqual(r.mc_specs_violated,1)
        self.assertTrue(r.mc_violations[0]["trace"])
    def test_structured_counterexample_worker_serialization(self):
        from stbench.cli import problems,reference
        p=next(p for p in problems() if p.pid=="self-medium-01")
        p.mc_max_depth=1;p.mc_max_traces=10;p.mc_max_seconds=2
        p.specs[0].ltl="G(FALSE)"
        r=evaluate(reference(p),p,model_check=True,timeout_s=4)
        self.assertEqual(verification_status(r),"violated")
        self.assertTrue(r.mc_violations[0]["trace"])
        json.dumps(r.to_dict())
    def test_no_ltl_prompt(self):
        p=problem();p.specs[0].text="SPEC_SENTINEL"
        self.assertIn("SPEC_SENTINEL",build_task_prompt(p))
        self.assertNotIn("SPEC_SENTINEL",build_task_prompt(p,include_ltl=False))
    def test_feedback_does_not_leak_nested_expected_or_notes(self):
        r=StageResult(compiles=True,tests_total=1)
        r.cases=[CaseResult("hidden",False,message="secret 782.35",
            expected={"buffer":[{"val":782.35}]},hint="secret solution",actual={"buffer":3})]
        text=feedback_for_agent(r)
        for secret in ("782.35","secret","solution","实际"):
            self.assertNotIn(secret,text)
        self.assertIn("buffer",text)
    def test_missing_extra_wrong_direction_interface(self):
        for bad in [CODE.replace("VAR_INPUT","VAR_IN_OUT"),CODE.replace("a:BOOL;","a:BOOL; extra:BOOL;")]:
            r=local_tests(bad,problem())
            self.assertFalse(r.compiles);self.assertEqual(r.tests_passed,0)
    def test_wrong_pou_kind(self):
        r=local_tests(CODE.replace("FUNCTION_BLOCK","PROGRAM"),problem())
        self.assertFalse(r.compiles)
    def test_explicit_mc_input_domain_is_used(self):
        from stbench.st.driver import _collect_domains
        p=problem();p.mc_inputs={"a":[False]}
        self.assertEqual(_collect_domains(p)["a"],[False])
    def test_string_capacity_checked(self):
        p=Problem.from_dict(dict(pid="s",source="selfmade",difficulty="easy",title="s",requirements="s",
            variables=[dict(name="s",data_type="STRING(254)",direction="input")]))
        good="FUNCTION_BLOCK FB\nVAR_INPUT s:STRING(254); END_VAR\nEND_FUNCTION_BLOCK"
        self.assertTrue(local_tests(good,p).compiles)
        self.assertFalse(local_tests(good.replace("254","80"),p).compiles)
    def test_truncated_is_not_verified(self):
        r=StageResult(compiles=True,mc_executed=True,mc_specs_total=1,mc_specs_hold=1,mc_truncated=True)
        self.assertFalse(r.specs_all_hold);self.assertEqual(verification_status(r),"truncated")
    def test_timeout_includes_first_enumeration(self):
        with patch("stbench.modelcheck.time.monotonic",side_effect=[0,2,2,2]):
            r=check(CODE,{"S":"G(b = a)"},InputSpace({"a":[True,False]}),max_seconds=1)
        self.assertTrue(r.error or r.truncated)
    def test_process_deadline(self):
        r=evaluate(CODE,problem(),timeout_s=.001)
        self.assertEqual(verification_status(r),"timeout")
    def test_cache_preserves_verification(self):
        with tempfile.TemporaryDirectory() as directory:
            a=evaluate(CODE,problem(),cache_dir=Path(directory))
            b=evaluate(CODE,problem(),cache_dir=Path(directory))
            self.assertEqual(verification_status(a),verification_status(b))
            self.assertTrue(b.mc_executed)
            self.assertTrue(b.evidence_metadata["cache_hit"])
    def test_repeat_terminates(self):
        p=problem();p.test_cases[0].expected={"b":False}
        provider=MockProvider(script=[CODE,CODE,CODE])
        r=solve_problem(p,Solver(provider,model_check=False))
        self.assertEqual(r.stop_reason,"repeated_candidate");self.assertEqual(len(r.attempts),2)
    def test_resume_keeps_results_and_rejects_changed_config(self):
        with tempfile.TemporaryDirectory() as directory:
            p=problem();s=Solver(MockProvider(script=CODE),model_check=False)
            a=solve_problem(p,s,log_dir=Path(directory))
            b=solve_problem(p,s,log_dir=Path(directory),resume=True)
            self.assertEqual(a.to_dict(),b.to_dict())
            s.include_ltl=False
            with self.assertRaises(ValueError):solve_problem(p,s,log_dir=Path(directory),resume=True)
    def test_live_disabled_before_network(self):
        with patch("stbench.providers.base._post_json") as post:
            with self.assertRaises(ProviderError):
                OpenAICompatProvider("not-selected","https://example.com",api_key="unused").generate([])
            post.assert_not_called()
        for cfg in ({},{"live_enabled":True},{"live_enabled":True,"budget_cny":10,"models":[]}):
            with self.assertRaises(ProviderError):validate_live_config(cfg)
    def test_budget_stops_before_send_and_survives_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/"ledger.json";b=Budget(path,1)
            index=b.reserve(.8)
            with self.assertRaises(ProviderError):b.reserve(.3)
            b.settle(index,.2);b2=Budget(path,1)
            self.assertAlmostEqual(b2.state["spent_cny"],.2)
    def test_native_unavailable_not_pass(self):
        r=CodesysBackend({"codesys_executable":"E:/PLC_Dev/not-installed.exe"}).compile(CODE,problem())
        self.assertEqual(r.status,"unavailable")
    def test_native_failure_gates_functional_and_formal_checks(self):
        from stbench.platforms import CompileResult
        class FailingBackend:
            name="fixture-native"
            timeout=1
            def compile(self,src,p):return CompileResult(self.name,"failed")
        r=evaluate(CODE,problem(),backends=(FailingBackend(),),timeout_s=2)
        self.assertTrue(r.compiles)
        self.assertEqual(r.tests_passed,0)
        self.assertEqual(r.tests_total,2)
        self.assertFalse(r.mc_executed)
        self.assertEqual(r.platform_results["fixture-native"]["status"],"failed")
    def test_empty_cases_not_solved(self):
        p=problem();p.test_cases=[]
        r=solve_problem(p,Solver(MockProvider(script=CODE),model_check=False,max_iters=1))
        self.assertFalse(r.solved)
    def test_task_level_denominators(self):
        a=solve_problem(problem(),Solver(MockProvider(script=CODE),model_check=False))
        p=problem();b=solve_problem(p,Solver(MockProvider(script="bad"),model_check=False,max_iters=1))
        s=summarize([a,b])
        self.assertEqual(s["tests_total"],4)
        self.assertEqual(s["compile_rate"],.5)
    def test_timeout_before_first_call_keeps_case_denominator(self):
        r=solve_problem(problem(),Solver(MockProvider(script=CODE),model_check=False,task_seconds=0))
        self.assertEqual(len(r.attempts),0)
        self.assertEqual(summarize([r])["tests_total"],2)
    def test_duplicate_candidate_keeps_actual_cost_and_model(self):
        class ChargedMock(MockProvider):
            def generate(self,messages):
                r=super().generate(messages)
                r.cost_cny=.2;r.model="actual-fixture"
                return r
        p=problem();p.test_cases[0].expected={"b":False}
        r=solve_problem(p,Solver(ChargedMock(script=[CODE,CODE]),model_check=False))
        self.assertAlmostEqual(summarize([r])["total_cost_cny"],.4)
        self.assertEqual(r.attempts[-1].actual_model,"actual-fixture")
    def test_all_references_and_expected_values(self):
        passed=total=0
        for group in ("public","selfmade"):
            for path in sorted((ROOT/"datasets"/group).glob("*.json")):
                if path.name.startswith("_"):continue
                p=Problem.load(path)
                src=(path.parent/"tests"/(p.pid+".reference.st")).read_text(encoding="utf-8")
                r=local_tests(src,p)
                self.assertTrue(r.compiles,(p.pid,r.compile_errors))
                self.assertTrue(r.all_tests_passed,(p.pid,r.failure_summary))
                passed+=r.tests_passed;total+=r.tests_total
        self.assertEqual((passed,total),(435,435))

if __name__=="__main__":
    unittest.main()

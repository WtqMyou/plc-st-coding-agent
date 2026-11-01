"""v1.2 import guards and independent edge cases for the five process tasks."""
import hashlib
import json
import unittest
import contextlib
import io
import runpy
import sys
from unittest.mock import patch
from pathlib import Path
from stbench.cli import problems, reference, doctor, config
from stbench.evaluation import local_tests
from stbench.schema import TestCase
from stbench.modelcheck import check, InputSpace

ROOT = Path(__file__).resolve().parents[1]


class Update(unittest.TestCase):
    def task(self, pid, inputs, expected, source=None):
        p = next(p for p in problems() if p.pid == pid)
        p.test_cases = [TestCase.from_dict(dict(tc_id=str(i), inputs=a, expected=b))
                        for i, (a, b) in enumerate(zip(inputs, expected))]
        return local_tests(source or reference(p), p)

    def test_upstream_57_cases_are_unchanged(self):
        manifest = json.loads((ROOT / "evidence/upstream_v1.2_cases.json").read_text(encoding="utf-8"))
        tasks = {p.pid: p for p in problems()}
        self.assertEqual(len(manifest["entries"]), 5)
        for row in manifest["entries"]:
            raw = json.loads((ROOT / "datasets/selfmade" / (row["pid"] + ".json")).read_text(encoding="utf-8"))
            digest = hashlib.sha256(json.dumps(raw["test_cases"], sort_keys=True, ensure_ascii=False).encode()).hexdigest()
            self.assertEqual(digest, row["test_cases_sha256"])
        self.assertEqual(sum(len(tasks[r["pid"]].test_cases) for r in manifest["entries"]), 57)

    def test_dynamic_counts_and_index(self):
        ps = problems()
        self.assertEqual((len(ps), sum(len(p.specs) for p in ps), sum(bool(s.ltl) for p in ps for s in p.specs)), (35, 203, 175))
        self.assertEqual(doctor(config(""))["expected_cases"], 435)
        index = json.loads((ROOT / "datasets/selfmade/_index.json").read_text(encoding="utf-8"))
        self.assertEqual((len(index), sum(r["n_cases"] for r in index)), (15, 134))

    def test_hex_ltl_literal_is_evaluated(self):
        src = "FUNCTION_BLOCK FB VAR_INPUT a:BOOL; END_VAR VAR_OUTPUT mask:WORD; END_VAR mask:=16#0008; END_FUNCTION_BLOCK"
        r = check(src, {"S": "G(mask = 16#0008)"}, InputSpace({"a": [False]}), max_depth=2, max_traces=20)
        self.assertFalse(r.error)
        self.assertTrue(r.specs[0].holds)

    def test_flame_latch_held_reset_cannot_clear_later(self):
        inputs = [dict(runRequest=True, flameOK=False, resetBtn=True),
                  dict(runRequest=False, flameOK=False, resetBtn=True),
                  dict(runRequest=False, flameOK=False, resetBtn=False),
                  dict(runRequest=False, flameOK=False, resetBtn=True)]
        r = self.task("self-hard-05", inputs, [dict(tripLatched=v, fuelPermit=False) for v in (True, True, True, False)])
        self.assertTrue(r.all_tests_passed, r.failure_summary)

    def test_steam_units_and_held_reset(self):
        p = next(p for p in problems() if p.pid == "self-medium-05")
        self.assertIn("kg/s", p.requirements)
        base = dict(enable=True, dt=1., steamFlow=20., fuelFlow=1., steamTemp=450., steamPressure=3800.)
        r = self.task(p.pid, [dict(base, resetBtn=v) for v in (False, True, True)],
                      [dict(qualifiedTon=.02), dict(qualifiedTon=0.), dict(qualifiedTon=.02)])
        self.assertTrue(r.all_tests_passed, r.failure_summary)

    def test_fuzzy_reset_clears_power_even_with_nonzero_bias(self):
        base = dict(enable=True, sensorValid=True, dt=1., bias=50., setpoint=100., temperature=90.)
        r = self.task("self-medium-06", [dict(base, resetBtn=v) for v in (False, True, True)],
                      [dict(power=70.), dict(power=0., correction=0.), dict(power=70.)])
        self.assertTrue(r.all_tests_passed, r.failure_summary)

    def test_overpressure_evidence_break_restarts_count_and_catches_old_bug(self):
        base = dict(runRequest=True, pressureValid=True, fuelFlow=1., steamFlow=20., outletCmd=60, outletFeedback=0, resetBtn=False)
        inputs = [dict(base, pressure=p) for p in (4600., 4600., 4400., 4600., 4600., 4600.)]
        expected = [dict(currentCauseMask=m) for m in (8, 8, 0, 8, 8, 2)]
        r = self.task("self-hard-06", inputs, expected)
        self.assertTrue(r.all_tests_passed, r.failure_summary)
        p = next(p for p in problems() if p.pid == "self-hard-06")
        old = reference(p).replace("ELSE\n valveCnt := 0;\nEND_IF;\nIF tripMem", "END_IF;\nIF tripMem")
        self.assertNotEqual(old, reference(p))
        self.assertFalse(self.task(p.pid, inputs, expected, source=old).all_tests_passed)

    def test_pi_consecutive_switches_hold_output(self):
        base = dict(resetBtn=False, dt=1., tempSP=100., tempPV=90., flowPV=10., manualFlowSP=10., manualValve=40.)
        inputs = [dict(base, mode=m) for m in (0, 0, 1, 2, 0)]
        r = self.task("self-hard-07", inputs,
                      [dict(valveCommand=40., normalMode=m) for m in (False, True, False, False, False)])
        self.assertTrue(r.all_tests_passed, r.failure_summary)

    def test_single_task_cli_cannot_report_truncated_as_pass(self):
        from stbench.st.driver import StageResult
        main = runpy.run_path(str(ROOT / "scripts/verify_one.py"))["main"]
        for status in ("truncated", "inconclusive", "bounded"):
            result = StageResult(compiles=True, tests_total=1, tests_passed=1, mc_executed=True,
                                 mc_specs_total=1, mc_specs_hold=1, mc_truncated=status=="truncated",
                                 mc_specs_inconclusive=int(status=="inconclusive"))
            with self.subTest(status=status), patch.object(sys, "argv", ["verify_one", "self-hard-06"]), \
                 patch("stbench.evaluation.evaluate", return_value=result), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(main(), int(status!="bounded"))


if __name__ == "__main__":
    unittest.main()

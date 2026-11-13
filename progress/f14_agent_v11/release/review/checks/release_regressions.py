"""Reproduce elapsed-time boundary errors and the archived mutable-output defect."""
import json
from dataclasses import replace
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from stbench.schema import Problem
from stbench.evaluation import local_tests
from stbench.spec_observers import observer_for

def load(pid):
    p = ROOT / "datasets/public" / (pid + ".json")
    return Problem.load(p), (p.parent / "tests" / (pid + ".reference.st")).read_text(encoding="utf-8")

def replay():
    results = {}
    mutations = {
        "public-medium-04": [("trip-at-equality", "T#5001ms", "T#5s"),
                             ("release-early", "T#3s", "T#2s")],
        "public-medium-07": [("fan-early", "T#30s", "T#29s")],
    }
    for pid, changes in mutations.items():
        p, src = load(pid)
        correct = local_tests(src, p)
        assert correct.compiles and correct.all_tests_passed, pid
        results[pid] = {}
        for label, before, after in changes:
            assert before in src
            wrong = local_tests(src.replace(before, after), p)
            failed = [c for c in wrong.cases if not c.passed]
            assert wrong.compiles and failed, (pid, label)
            fail = failed[0]
            group = next(c.group for c in p.test_cases if c.tc_id == fail.tc_id)
            inputs = []
            for c in p.test_cases:
                if c.group == group:
                    inputs.append(dict(tc_id=c.tc_id, inputs=c.inputs, scan_interval_ms=c.scan_interval_ms))
                if c.tc_id == fail.tc_id:
                    break
            results[pid][label] = dict(trace=inputs, expected=fail.to_dict()["expected"],
                                      actual=fail.to_dict()["actual"], failures=len(failed))
    p, src = load("public-hard-03")
    full = local_tests(src, p)
    prefix = local_tests(src, replace(p, test_cases=p.test_cases[:2]))
    assert full.all_tests_passed and prefix.all_tests_passed
    early = full.cases[1].to_dict()["actual"]
    assert full.cases[1].tc_id == "h03-2" and early == prefix.cases[1].to_dict()["actual"]
    ids = [r["recipeid"] if "recipeid" in r else r["recipeID"] for r in early["recipe"][:2]]
    assert ids == [1, 0], ids
    results["public-hard-03"] = dict(case="h03-2", prefix_and_full_first_ids=ids)
    p, src = load("public-medium-08")
    observer = observer_for(p.provenance["r9_spec_policy"]["observer"])
    var = p.inputs[0].name.lower()
    for text, scored in (("01.2.3.4", False), ("0.2.3.4", True), ("01.2.3.999", True)):
        assert observer({var: text}, None, False)["__spec_ip_scored"] == scored, (text, var)
    results["public-medium-08"] = dict(leading_zero="unspecified", valid_zero="scored", out_of_range="scored")
    return results

if __name__ == "__main__":
    print(json.dumps(replay(), ensure_ascii=False, indent=2))

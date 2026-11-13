"""Replay the gate and fill contract checks with the local functional judge."""
import argparse
import hashlib
import json
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT))
from stbench.evaluation import local_tests
from stbench.reference_certificates import Encoder, solve
from stbench.schema import Problem


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_task(pid):
    path = ROOT / "datasets" / "selfmade" / (pid + ".json")
    source = path.parent / "tests" / (pid + ".reference.st")
    return json.loads(path.read_bytes()), source.read_text(encoding="utf-8")


def score(data, code):
    groups = defaultdict(list)
    for case in data["test_cases"]:
        groups[case.get("group", ""), case.get("mode") or data["case_mode"]].append(case)
    failures = {}
    passed = 0
    for (_, mode), cases in groups.items():
        problem = Problem.from_dict({**data, "case_mode": mode, "test_cases": cases})
        result = local_tests(code, problem)
        assert result.compiles and result.tests_total == len(cases)
        passed += result.tests_passed
        for case in result.cases:
            if not case.passed:
                failures[case.tc_id] = case.message
    return {"passed": passed, "total": len(data["test_cases"]), "failures": failures}


def reference_check(data, code, prove):
    results = score(data, code)
    assert not results["failures"]
    if prove:
        problem = Problem.from_dict(data)
        query = Encoder().build(problem, code)
        answer = solve(query, 30000)
        assert answer == "unsat", (data["pid"], answer)
        results["bounded_search"] = {
            "depth": problem.mc_max_depth,
            "properties": [s.sid for s in problem.specs if s.ltl],
            "negated_conjunction": answer,
            "query_sha256": sha(query.encode()),
        }
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prove", action="store_true", help="Run Z3 on the declared eight-scan domains.")
    args = parser.parse_args()
    gate, ref_gate = read_task("self-medium-03")
    fill, ref_fill = read_task("self-medium-04")
    pump, ref_pump = read_task("self-hard-04")
    results = {
        "gate_reference": reference_check(gate, ref_gate, args.prove),
        "fill_reference": reference_check(fill, ref_fill, args.prove),
        "pump_reference": score(pump, ref_pump),
        "selected_fill_candidates": {},
    }
    assert not results["pump_reference"]["failures"]
    # This is the F1.3 closing-state choice: a first obstacle clears motion
    # to idle, so a one-scan pulse never latches the fault.
    latch = "IF obstacle THEN\n    state := 3;"
    assert ref_gate.count(latch) == 1
    old_gate = ref_gate.replace(latch, "IF obstacle THEN\n    IF state = 2 THEN state := 0; ELSE state := 3; END_IF;")
    results["gate_delayed_latch"] = score(gate, old_gate)
    assert "m5" in results["gate_delayed_latch"]["failures"]

    hashes = {
        "custom_deepseek-v4pro": "2fe0dfe47093d4db9e7f1499adcffa38bf99f04d0405718d151b6b6488b84944",
        "codex_deepseek-v4pro": "0c52a9eb5d313013aec399ea10ab24b4592a3711024eee48272282ff26de6a11",
    }
    original_cases = [c for c in fill["test_cases"] if not c["tc_id"].startswith("f14-")]
    for arm, expected in hashes.items():
        code = (HERE / ("fill_" + arm + ".st")).read_text(encoding="utf-8").rstrip("\n")
        assert sha(code.encode()) == expected
        baseline = score({**fill, "test_cases": original_cases}, code)
        current = score(fill, code)
        assert (baseline["passed"], baseline["total"]) == (23, 27)
        assert set(baseline["failures"]) == {"fill-limit-2", "fill-limit-3", "fill-limit-4", "fill-limit-7"}
        assert "f14-close-ack-2" in current["failures"]
        results["selected_fill_candidates"][arm] = {
            "source_sha256": expected, "original": baseline, "revised": current
        }
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

"""Replay the selected archived answer and a four-sample arithmetic error."""
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT))
from stbench.evaluation import local_tests
from stbench.schema import Problem


def score(data, code):
    result = local_tests(code, Problem.from_dict(data))
    assert result.compiles, result.compile_errors
    return {
        "compiles": result.compiles,
        "passed": result.tests_passed,
        "total": result.tests_total,
        "failures": {
            c.tc_id: {"expected": c.expected, "actual": c.actual}
            for c in result.cases if not c.passed
        },
    }


def main():
    problem = ROOT / "datasets" / "public" / "public-medium-03.json"
    data = json.loads(problem.read_bytes())
    reference = (problem.parent / "tests" / "public-medium-03.reference.st").read_text(encoding="utf-8")
    archived = (HERE / "selected.st").read_bytes()
    source_hash = hashlib.sha256(archived).hexdigest()
    assert source_hash == "e1e1500bf287c1ca61e560953eb8bf19949d09d025c307a1a0775d508c385a1b"
    candidate = archived.decode("utf-8")

    # Restore the three original assertions to replay the 17 prior test cases.
    original_cases = []
    for case in data["test_cases"]:
        if case.get("group") == "fixed-four":
            continue
        cid = case["tc_id"]
        if cid in {"s8", "s9", "s10"}:
            expected = {"average": 57.5, "windowSizeReached": True}
            if cid != "s8":
                expected.update(error=True, status=33280)
            case = {**case, "expected": expected, "expect_full": cid == "s9"}
        original_cases.append(case)
    prior = {**data, "test_cases": original_cases}
    correct = "average := sum / n;"
    assert reference.count(correct) == 1
    wrong = "IF n = 4 THEN average := sum / 3; ELSE average := sum / n; END_IF;"
    mutant = reference.replace(correct, wrong)
    results = {
        "selected_answer_sha256": source_hash,
        "prior_candidate": score(prior, candidate),
        "current_candidate": score(data, candidate),
        "current_reference": score(data, reference),
        "current_wrong_divisor": score(data, mutant),
    }
    prior_score = results["prior_candidate"]
    assert (prior_score["passed"], prior_score["total"]) == (14, 17)
    assert set(prior_score["failures"]) == {"s8", "s9", "s10"}
    for key in ("current_candidate", "current_reference"):
        assert (results[key]["passed"], results[key]["total"]) == (21, 21)
    assert set(results["current_wrong_divisor"]["failures"]) == {"fixed-four-4"}
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

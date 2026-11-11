"""Reproduce F1.4 public-task regression results without a model or network."""

from itertools import product
from pathlib import Path
import argparse
import hashlib
import json
import sys
from copy import deepcopy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from stbench.evaluation import local_tests
from stbench.fifo_binding_check import search
from stbench.public_input_contracts import scan_contract, valid_modes, valid_route
from stbench.schema import Problem
from stbench.st.driver import StageResult, _attach_model_check, _collect_domains

FIXTURES = ROOT / "review/fixtures/agent_9772562"
SOURCE_COMMIT = "97725624b924990f6cdf38563d1fc17f5280502f"
ARCHIVE = {
    "conveyor": ("02", "custom_deepseek-v4pro", 1, "b29367282418e78318da844145b72bf4dd8ba18b000b32a036e457ddb0e0ea33"),
    "recipe": ("03", "custom_deepseek-v4pro", 0, "c8e4e1e1914390b93056b2a05455eb2731133cf056936165370e1c70b4b3d7b3"),
    "arm_one_step": ("05", "custom_deepseek-v4pro", 1, "910412f1a7dde9a5579ee814d416913442a839061d956840c5fa89ac68496e34"),
    "arm_restart": ("05", "codex_deepseek-v4pro", 0, "697396aab76add3a1d9842351bb9c2cdc9dc9dedf2bd72b0bba96ae4deb08e87"),
}


def functionality(problem, code, failures=()):
    result = local_tests(code, problem)
    actual = [c.tc_id for c in result.cases if not c.passed]
    assert result.compiles and actual == list(failures), (problem.pid, actual, result.failure_summary)
    assert result.tests_total == len(problem.test_cases) == len(result.cases)
    return dict(passed=result.tests_passed, total=result.tests_total, failed=actual)


def fifo_formal(problem, code):
    result = StageResult(compiles=True)
    _attach_model_check(code, problem, result)
    assert not result.mc_error and not result.mc_truncated
    report = result.evidence_metadata["caller_binding_search"]
    assert report["legal_inputs_per_scan"] == 6 and not report["include_conflicting_requests"]
    return dict(formulas=result.mc_specs_total, hold=result.mc_specs_hold,
                violations={v["id"]: v["at"] for v in result.mc_violations},
                legal_inputs_per_scan=report["legal_inputs_per_scan"])


def analog_checks():
    base = ROOT / "datasets/public"
    problem = Problem.load(base / "public-medium-02.json")
    source = (base / "tests/public-medium-02.reference.st").read_text("utf8")

    def formal(src):
        result = StageResult(compiles=True)
        _attach_model_check(src, problem, result)
        assert not result.mc_error and not result.mc_truncated
        return dict(hold=result.mc_specs_hold, total=result.mc_specs_total,
                    **result.evidence_metadata["caller_binding_search"])

    limited = source.replace("TO count - 1", "TO MIN(count, 8) - 1")
    shared_base = source.replace("analogValues[rawBase + i]", "analogValues[idx]")
    tie = source.replace("channels[idx].retVal := 16#8001;",
                         "IF channels[idx].hiLIM <= channels[idx].loLIM THEN channels[idx].retVal := 16#8002; "
                         "ELSE channels[idx].retVal := 16#8001; END_IF;").replace("16#0000;", "42;")
    result = dict(reference=functionality(problem, source), formal=formal(source),
                  old_limit=functionality(problem, limited, ["f14-ten-channels"]), old_limit_formal=formal(limited),
                  shared_base=functionality(problem, shared_base, ["f14-raw-shorter", "f14-channel-shorter",
                                                                  "f14-ten-channels", "f14-double-error"]),
                  alternative_error_order_and_success_code=functionality(problem, tie), alternative_formal=formal(tie))
    assert result["formal"]["hold"] == result["alternative_formal"]["hold"] == result["formal"]["total"] == 4
    assert result["formal"]["transitions"] == 260
    assert [(v["id"], v["fixture"], v["inputs"]) for v in result["old_limit_formal"]["violations"]] == [
        ("S8", "f14-ten-channels", [9])]
    return result


def main():
    problems = {}
    sources = {}
    evidence = dict(source_commit=SOURCE_COMMIT, reference={}, archived_candidates={})
    for k in ("02", "03", "04", "05"):
        pid = "public-hard-" + k
        base = ROOT / "datasets/public"
        problems[k] = Problem.load(base / (pid + ".json"))
        sources[k] = (base / "tests" / (pid + ".reference.st")).read_text("utf8")
        evidence["reference"][pid] = functionality(problems[k], sources[k])

    expected_failures = dict(conveyor=["f14-arrival-1"],
                             recipe=["f14-add-deleteRecipe", "f14-add-modifyRecipe"],
                             arm_one_step=[], arm_restart=["h05-16", "h05-18"])
    for name, (k, condition, attempt, expected_hash) in ARCHIVE.items():
        raw = (FIXTURES / (name + ".st")).read_bytes()
        assert hashlib.sha256(raw).hexdigest() == expected_hash, name
        evidence["archived_candidates"][name] = dict(
            condition=condition, selected_zero_based_attempt=attempt, sha256=expected_hash,
            job_path=f"progress/evidence/full_r8_20261110b/jobs/{condition}/public-hard-{k}.json",
            **functionality(problems[k], raw.decode("utf8"), expected_failures[name]))

    # An alternative implementation can add first, then successfully delete/modify
    # the new record. Both that answer and the original error response must score.
    serial = sources["03"]
    for key in ("IF dEdge THEN", "IF mEdge THEN"):
        assert serial.count(key) == 1
        serial = serial.replace(key, key + "\n  IF recipeAdded THEN hitIdx := freeIdx; END_IF;")
    evidence["serial_recipe"] = functionality(problems["03"], serial)

    for c in problems["02"].test_cases:
        v = {**c.const_inputs, **c.inputs}
        assert valid_route(v["processLength"], v["processSequence"]), c.tc_id
    for c in problems["05"].test_cases:
        assert valid_modes(*(c.inputs.get(k, False) for k in
                             ("ManualMode", "SingleStepMode", "SingleCycleMode", "ContinuousMode")))
    arm_domains = {k: [False, True] for k in ("ManualMode", "SingleStepMode", "SingleCycleMode", "ContinuousMode")}
    arm_filter, size = scan_contract("public-hard-05", arm_domains)
    assert size == sum(arm_filter(x) for x in product(*arm_domains.values())) == 5
    route_filter, size = scan_contract("public-hard-02", {"processLength": [1, 2], "processSequence": [[2, 5, 0, 0, 0, 0, 0, 0]]})
    assert size == 1 and not route_filter((1, [2, 5, 0, 0, 0, 0, 0, 0]))

    fifo, src = problems["04"], sources["04"]
    assert all(not (c.inputs.get("enqueue") and c.inputs.get("dequeue")) for c in fifo.test_cases)
    evidence["fifo_reference"] = fifo_formal(fifo, src)
    assert evidence["fifo_reference"]["hold"] == 7
    # Replay the team's exact capacity-2 five-scan input as a proposed model
    # domain fixture. The first four legal calls model successfully; introducing
    # the simultaneous request on the fifth makes the profile reject the trace.
    malformed = deepcopy(fifo)
    template = next(c for c in fifo.test_cases if c.group == "bound-2" and "buffer" in c.init)
    malformed.test_cases = [c for c in malformed.test_cases if c.group != "bound-2"]
    original_inputs = []
    for i, (enq, deq) in enumerate(((True,False),(False,False),(True,False),(False,False),(True,True)), 1):
        row = deepcopy(template)
        row.tc_id = "archived-" + str(i)
        row.init = row.init if i == 1 else {}
        row.const_inputs = {}
        row.inputs = dict(enqueue=enq, dequeue=deq, reset=False)
        original_inputs.append(row.inputs)
        malformed.test_cases.append(row)
        if i >= 4:
            out = StageResult(compiles=True)
            _attach_model_check(src,malformed,out)
            if i == 4:
                assert not out.mc_error and out.mc_specs_hold == 7
            else:
                assert "prohibits simultaneous" in out.mc_error and out.mc_specs_hold == 0
    evidence["fifo_archived_fifth_input"] = dict(capacity=2, inputs=original_inputs,
        legal_through_scan=4, rejected_scan=5, rejection=out.mc_error)
    sticky = src.replace("status := 16#0000;", "IF reset OR enEdge OR deEdge THEN status := 16#0000; END_IF;")
    assert sticky != src
    evidence["fifo_idle_status"] = dict(functional=functionality(fifo, sticky, ["f14-idle-after-empty"]),
                                      formal=fifo_formal(fifo, sticky))
    assert evidence["fifo_idle_status"]["formal"]["violations"] == {"S8": 2}

    # This artificial answer agrees with the reference on every legal call. Its
    # error is observable only if the checker admits conflicting request inputs.
    outside = src.replace("elementCount := count;", "elementCount := count; "
                          "IF enEdge AND deEdge AND count = cap THEN elementCount := count - 1; status := 16#8002; END_IF;")
    assert outside != src
    evidence["fifo_conflict_control"] = fifo_formal(fifo, outside)
    assert evidence["fifo_conflict_control"]["hold"] == 7
    audit = search(outside, fifo, _collect_domains(fifo), [(s.sid, s.ltl) for s in fifo.specs if s.ltl],
                   include_conflicting_requests=True)
    assert not audit["truncated"] and audit["legal_inputs_per_scan"] == 8
    assert any(v["id"] == "S4" and any(row["enqueue"] and row["dequeue"] for row in v["inputs"])
               for v in audit["violations"])
    evidence["analog"] = analog_checks()
    return evidence


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, help="save the JSON result")
    args = parser.parse_args()
    payload = json.dumps(main(), ensure_ascii=False, indent=2)
    print(payload)
    if args.output:
        args.output.write_text(payload + "\n", encoding="utf8")

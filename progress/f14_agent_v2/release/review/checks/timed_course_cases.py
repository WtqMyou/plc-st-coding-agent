"""Replay four timing references, alternative valid debounce policies and timing mistakes."""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from stbench.evaluation import local_tests
from stbench.schema import Problem
from stbench.st.interp import Interpreter
from stbench.st.typecheck import check_st


def check_clock():
    source = """FUNCTION_BLOCK TimingProbe
VAR_INPUT run : BOOL; END_VAR
VAR_OUTPUT done : BOOL; passed : TIME; scaled : LTIME; short : TIME; END_VAR
VAR onDelay : TON; preset : LTIME := T#5s; END_VAR
onDelay(PT := LTIME_TO_TIME(preset), IN := run, ET => passed, Q => done);
scaled := passed + LTIME#500us;
short := LTIME_TO_TIME(scaled);
END_FUNCTION_BLOCK"""
    parsed = check_st(source)
    if not parsed.ok:
        raise AssertionError(parsed.errors)
    interpreter = Interpreter(parsed.pou, parsed.structs)
    samples = [(True, 0, False, 0), (True, 4999, False, 4999),
               (True, 1, True, 5000), (True, 120, True, 5000),
               (False, 10, False, 0), (True, 40, False, 0)]
    for run, interval, done, elapsed in samples:
        interpreter.set_var("run", run)
        interpreter.scan(interval)
        actual = [interpreter.get_var(key) for key in ("done", "passed", "scaled", "short")]
        if actual != [done, elapsed, elapsed * 1000000 + 500000, elapsed]:
            raise AssertionError((interval, run, actual))


CHANGES = {
    "public-easy-04": [
        ("fixed-pump-cycle", "+ TIME_TO_LTIME(CycleTime)", "+ LTIME#1ms"),
        ("late-maintenance", ">= LTIME#500h", "> LTIME#500h"),
    ],
    "public-easy-05": [
        ("short-startup", "PT := T#5s", "PT := T#4s"),
        ("fixed-debounce", "PT := DebounceTime", "PT := T#750ms"),
    ],
    "public-easy-06": [
        ("short-on-delay", "PT := T#5s", "PT := T#4s"),
        ("count-every-scan", "AND NOT wasRunning AND", "AND"),
    ],
    "public-medium-06": [
        ("short-alarm-hold", "remaining := T#500ms", "remaining := T#20ms"),
        ("fixed-cutting-cycle", "+ TIME_TO_LTIME(CycleTime)", "+ LTIME#20ms"),
    ],
}

DEBOUNCE = {
    "public-easy-04": ("viscosityDelay", "PASTE_E_STOP_NC", "VFD_RUN"),
    "public-easy-05": ("gapDelay", "Weld_E_Stop_NC", "Operator_Alert"),
}


def check_debounce_policy(pid, source, problem):
    timer, permit, output = DEBOUNCE[pid]
    assignment = f"{output} := {timer}.Q;"
    gated = source.replace(assignment, f"{output} := {timer}.Q AND {permit};")
    results = []
    for policy, qualifier, valid in [
        ("preserve_completed", f"({permit} OR {timer}.Q)", True),
        ("preserve_incomplete", "TRUE", False),
    ]:
        end = "," if pid == "public-easy-04" else " AND"
        candidate = gated.replace("AND " + permit + end, "AND " + qualifier + end, 1)
        result = local_tests(candidate, problem)
        failures = [case for case in result.cases if not case.passed]
        if not result.compiles or bool(failures) == valid:
            raise AssertionError((pid, policy, result.failure_summary))
        results.append(dict(policy=policy, passed=result.tests_passed, total=result.tests_total,
                            failure=failures[0].to_dict() if failures else None))
    return results


def replay():
    check_clock()
    evidence = {}
    for pid, changes in CHANGES.items():
        folder = ROOT / "datasets" / "public"
        source = (folder / "tests" / (pid + ".reference.st")).read_text(encoding="utf8")
        problem = Problem.load(folder / (pid + ".json"))
        reference = local_tests(source, problem)
        if not reference.compiles or reference.tests_passed != len(problem.test_cases):
            raise AssertionError((pid, reference.failure_summary))
        rows = []
        for name, original, substitute in changes:
            if source.count(original) != 1:
                raise AssertionError((pid, original))
            mutant = local_tests(source.replace(original, substitute), problem)
            failures = [case for case in mutant.cases if not case.passed]
            if not mutant.compiles or not failures:
                raise AssertionError((pid, name, mutant.failure_summary))
            case = failures[0]
            observed = case.to_dict()
            fixture = next(c for c in problem.test_cases if c.tc_id == case.tc_id)
            rows.append(dict(change=name, replace=original, with_text=substitute,
                             group=fixture.group, first_failed=case.tc_id,
                             inputs=fixture.inputs, scan_interval_ms=fixture.scan_interval_ms,
                             cycles=fixture.cycles, expected=observed["expected"],
                             actual=observed["actual"],
                             failed_cases=len(failures)))
        evidence[pid] = dict(reference_passed=reference.tests_passed,
                             reference_total=reference.tests_total, mutants=rows)
        if pid in DEBOUNCE:
            evidence[pid]["emergency_policies"] = check_debounce_policy(pid, source, problem)
    return evidence


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    output = parser.parse_args().output
    data = json.dumps(replay(), ensure_ascii=False, indent=2)
    if output:
        output.write_text(data + "\n", encoding="utf8")
    else:
        print(data)

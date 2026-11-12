"""Re-run q48/S10 and the pump and batch regressions against the released dataset."""
import json
import sys
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from stbench.evaluation import local_tests
from stbench.ltl import evaluate
from stbench.modelcheck import snapshot, _atom_evaluator
from stbench.schema import Problem
from stbench.st.interp import Interpreter
from stbench.st.typecheck import check_st


def task(pid):
    base = ROOT / "datasets/selfmade"
    return Problem.load(base / f"{pid}.json"), (base / "tests" / f"{pid}.reference.st").read_text("utf8")


def change(source, old, new):
    assert source.count(old) == 1, old
    return source.replace(old, new)


def cases(src, p):
    r = local_tests(src,p)
    assert r.compiles and r.tests_total == len(p.test_cases)
    return dict(passed=r.tests_passed, total=r.tests_total, failed=[c.tc_id for c in r.cases if not c.passed])


def replay(src, p, steps, spec_ids):
    parsed = check_st(src)
    assert parsed.ok and parsed.pou
    m = Interpreter(parsed.pou, parsed.structs)
    before = deepcopy(snapshot(m))
    frames = []
    for scan in steps:
        assert set(scan) == {v.name for v in p.inputs}
        for name, value in scan.items():
            m.set_var(name, value)
        m.scan()
        frames.append(deepcopy(snapshot(m)))
    atom = _atom_evaluator(m.types, parsed.structs)
    formulas = {s.sid:s.ltl for s in p.specs}
    checks = {}
    for sid in spec_ids:
        verdict = evaluate(formulas[sid],frames,atom,init_snapshot=before)
        assert not verdict.inconclusive
        checks[sid] = dict(holds=verdict.holds, first_failure_scan=verdict.counterexample_at)
    return dict(last_output={v.name:frames[-1][v.name.lower()] for v in p.outputs}, rules=checks)


def interlock():
    p,src = task("self-hard-06")
    seq = [c for c in p.test_cases if not c.group]
    last = seq[-1]
    assert len(seq) == 48 and last.tc_id == "peer-q48"
    assert all(c.cycles == 1 and not c.init for c in seq)
    inputs = [c.const_inputs | c.inputs for c in seq]
    rules = ["S10","N10-S10"]
    ref = replay(src, p, inputs, rules)
    assert ref["last_output"] == last.expected
    assert all(v["holds"] for v in ref["rules"].values())
    result = dict(task=p.pid, source_case_id="q48", release_case_id=last.tc_id, scan=48, inputs=inputs[-1],
                  expected=last.expected, reference=ref, reference_score=cases(src,p), mutated={})
    for mask in (7,4,0):
        anchor = "currentCauseMask := 16#0008;"
        mod = change(src, anchor,
                     f"IF fuelFlow = 3.0 AND steamFlow = 20.0 THEN currentCauseMask := {mask}; "
                     f"ELSE {anchor} END_IF;")
        r = replay(mod, p, inputs, rules)
        score = cases(mod,p)
        assert r["last_output"]["currentCauseMask"] == r["last_output"]["latchedCauseMask"] == mask
        assert score["failed"] == [last.tc_id] and r["rules"]["N10-S10"]["first_failure_scan"] == 48
        assert r["rules"]["S10"]["holds"] == (mask != 4)
        result["mutated"][str(mask)] = dict(functional=score, concrete_trace=r)
    return result


def other():
    pump, pump_src = task("self-hard-04")
    batch, batch_src = task("self-hard-02")
    tests = [
        ("pump_exactly_50", pump,pump_src,"S3","leadPump",1,
         [dict(demand=1,runHours=[0,100,200,300,400],rotated=False),
          dict(demand=1,runHours=[150,100,200,300,400],rotated=True)],
         " - runHours[best]) > 50)", " - runHours[best]) >= 50)"),
        ("pump_no_request", pump,pump_src,"S6","leadPump",1,
         [dict(demand=1,runHours=[0,100,200,300,400],rotated=False),
          dict(demand=1,runHours=[151,100,200,300,400],rotated=False)],
         "IF rotated AND ((", "IF TRUE AND (("),
        ("batch_no_command_after_completion", batch,batch_src,"S4","phase",3,
         [dict(startBtn=v, abortBtn=False, setpoint=100, pv=50, maxDuration=1) for v in [True,False,False]],
         "ELSIF phase = 1 OR phase = 2 THEN", "ELSIF phase = 3 THEN phase := 0; ELSIF phase = 1 OR phase = 2 THEN"),
    ]
    rows = {}
    for label,problem,src,sid,output,expected,inputs,old,new in tests:
        mod = change(src,old,new)
        ref = replay(src,problem,inputs,[sid])
        bad = replay(mod,problem,inputs,[sid])
        assert ref["last_output"][output] == expected and ref["rules"][sid]["holds"]
        assert bad["last_output"][output] != expected and bad["rules"][sid]["first_failure_scan"] == len(inputs)
        rows[label] = dict(task=problem.pid, inputs=inputs, output=output, expected=expected,
                           mutant_actual=bad["last_output"][output], expected_formula=sid, reference=ref, mutant=bad,
                           functional=cases(mod,problem), mutation={"from":old, "to":new})
    return rows


if __name__ == "__main__":
    result = dict(interlock=interlock(), **other())
    print(json.dumps(result,ensure_ascii=False,indent=2))

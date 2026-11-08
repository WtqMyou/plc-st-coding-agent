"""Read-only comparison of the submitted review and v1.3 package; no model calls."""
from __future__ import annotations

import argparse
import copy
from dataclasses import asdict
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import zipfile

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "agent_dev_r9_stage3"
INBOX = REPO / "11.8 复核记录+意见"
FIVE = ["self-hard-05", "self-hard-06", "self-hard-07", "self-medium-05", "self-medium-06"]
sys.path.insert(0, str(SOURCE))
from stbench.schema import Problem
from stbench.portability import adapt
from stbench.spec_policy import apply
from stbench.evaluation import check_interface
from stbench.st.driver import verify, verify_sequence
from stbench.st.frontend import compile_st
from stbench.st.typecheck import typecheck
from stbench.st.interp import Interpreter
from stbench.ltl import evaluate
from stbench.modelcheck import _atom_evaluator


def sha(data):
    return hashlib.sha256(data).hexdigest()


def stats(ds):
    return dict(tasks=len(ds), cases=sum(len(d["test_cases"]) for d in ds),
                properties=sum(len(d["specs"]) for d in ds),
                ltl=sum(bool(s.get("ltl", "").strip()) for d in ds for s in d["specs"]),
                simulation_only=sum(not bool(s.get("ltl", "").strip()) for d in ds for s in d["specs"]))


def replay(problem, src):
    """Evaluate formulas on the supplied sequence, without searching other traces."""
    parsed = typecheck(compile_st(src))
    if not parsed.ok or parsed.pou is None:
        return {"skipped": "Reference did not compile in the local checker"}
    interp = Interpreter(parsed.pou, parsed.structs)
    initial = copy.deepcopy(interp.mem)
    trace, case_ids = [], []
    for tc in problem.test_cases:
        if (tc.mode or problem.case_mode) != "sequence":
            continue
        for k, v in tc.init.items():
            interp.set_var(k, v)
        vec = {k.lower(): v for k, v in tc.inputs.items()}
        const = {k.lower(): v for k, v in tc.const_inputs.items()}
        for k, v in const.items():
            interp.set_var(k, v)
        for v in problem.inputs:
            name = v.name.lower()
            if name in vec:
                interp.set_var(v.name, vec[name])
            elif name not in const and interp.types.get(name, "").upper() == "BOOL":
                interp.set_var(v.name, False)
        for _ in range(max(1, tc.cycles)):
            interp.scan()
            trace.append(copy.deepcopy(interp.mem))
            case_ids.append(tc.tc_id)
    out = []
    for s in problem.specs:
        if not s.ltl:
            continue
        try:
            v = evaluate(s.ltl, trace, _atom_evaluator(interp.types, parsed.structs), init_snapshot=initial)
            row = dict(sid=s.sid, **asdict(v))
            if v.counterexample_at:
                row["case_id"] = case_ids[v.counterexample_at - 1]
        except Exception as exc:
            row = dict(sid=s.sid, error=f"{type(exc).__name__}: {exc}")
        out.append(row)
    return dict(scans=len(trace), formulas=out, scope="supplied reference test sequence only; not exhaustive model checking")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()
    spec = importlib.util.spec_from_file_location("review_dataset_audit", SOURCE / "scripts/check_dataset.py")
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)
    ledger = Path("E:/PLC_Dev/evidence/dmxapi_budget_75.json")
    ledger_before = ledger.read_bytes()
    result = dict(review_date="2026-11-08", model_calls=0, source="agent_dev_r9_stage3",
                  audit_script_sha256=sha(Path(__file__).read_bytes()),
                  inputs={p.name: dict(bytes=p.stat().st_size, sha256=sha(p.read_bytes()))
                          for p in sorted(INBOX.iterdir()) if p.is_file()},
                  counts={}, overlays=[], tasks=[], reference_checks=[], changed_public=[], changed_selfmade=[], probes=[])
    with zipfile.ZipFile(INBOX / "stbench_v1.3_20261028_完整工程.zip") as z:
        base = next(n[:-len("stbench/schema.py")] for n in z.namelist() if n.endswith("/stbench/schema.py"))
        new = {}
        for name in z.namelist():
            relative = name.removeprefix(base)
            if name.startswith(base) and relative.startswith("datasets/") and relative.endswith(".json") and relative.count("/") == 2 and not relative.endswith("_index.json"):
                new[relative] = json.loads(z.read(name))
        for label in ["agent_dev", "agent_dev_r9", "agent_dev_r9_stage3", "incoming_v1.3"]:
            for kind in ["public", "selfmade"]:
                ds = ([d for n, d in new.items() if n.startswith(f"datasets/{kind}/")]
                      if label == "incoming_v1.3" else
                      [json.loads(p.read_text("utf-8")) for p in sorted((REPO / label / "datasets" / kind).glob("*-*.json"))])
                result["counts"][f"{label}/{kind}"] = stats(ds)
        for kind in ["public", "selfmade"]:
            for n in sorted(k for k in new if k.startswith(f"datasets/{kind}/")):
                old = json.loads((SOURCE / n).read_text("utf-8"))
                if (SOURCE / n).read_bytes() != z.read(base + n):
                    result[f"changed_{kind}"].append(Path(n).stem)
                p = Problem.from_dict(old)
                before = {s.sid: s.ltl for s in p.specs}
                apply(p)
                result["overlays"].extend(dict(pid=p.pid, sid=s.sid, ltl=s.ltl) for s in p.specs if not before[s.sid] and s.ltl)
                p = Problem.from_dict(new[n])
                refname = f"datasets/{kind}/tests/{p.pid}.reference.st"
                ref = z.read(base + refname).decode("utf-8-sig")
                adapted, code, _ = adapt(p, ref, "codesys")
                checked = (verify_sequence(code, adapted, model_check=False) if adapted.case_mode == "sequence"
                           else verify(code, adapted, model_check=False))
                hard, warn = audit.audit_problem(p)
                row = dict(pid=p.pid, static_compiles=checked.compiles, tests_passed=checked.tests_passed,
                           tests_total=len(p.test_cases), interface_errors=check_interface(code, adapted),
                           dataset_errors=hard, dataset_warnings=warn,
                           failures=[c.to_dict() for c in checked.cases if not c.passed],
                           compile_errors=checked.compile_errors)
                result["reference_checks"].append(row)
                if p.pid in FIVE:
                    result["tasks"].append(dict(pid=p.pid, old_cases=len(old["test_cases"]), new_cases=len(p.test_cases),
                        old_specs=len(old["specs"]), new_specs=len(p.specs),
                        changed_top_level_keys=sorted(k for k in set(old) | set(new[n]) if old.get(k) != new[n].get(k)),
                        reference_unchanged=(SOURCE / refname).read_bytes() == z.read(base + refname),
                        raw_reference_formula_replay=replay(p, ref),
                        adapted_reference_formula_replay=replay(adapted, code)))
        fifo = Problem.from_dict(new["datasets/selfmade/self-hard-03.json"])
        result["fifo"] = dict(upstream_direction=next(v.direction.value for v in fifo.variables if v.name == "fifo"),
            current_provenance=json.loads((SOURCE / "datasets/selfmade/self-hard-03.json").read_text("utf-8"))["provenance"],
            explicit_fifo_case_channels=[dict(tc_id=c.tc_id, channel=k) for c in fifo.test_cases for k in ["inputs", "const_inputs", "init"] if "fifo" in getattr(c, k)])
        # Formula-only counterexamples: they demonstrate specification strength,
        # and are not claims about behavior of the supplied reference program.
        pi = new["datasets/selfmade/self-hard-07.json"]
        previous = dict(normalmode=False, mode=1, flowsp=10.0, valvecommand=9.2,
                        manualflowsp=10.0, manualvalve=99.0, fault=False, resetbtn=False)
        incorrect = dict(previous, mode=2, flowsp=30.0, valvecommand=99.0, manualflowsp=30.0)
        types = {v["name"].lower(): v["data_type"] for v in pi["variables"]}
        checks = [dict(sid=s["sid"], **asdict(evaluate(s["ltl"], [previous, incorrect],
                   _atom_evaluator(types, {})))) for s in pi["specs"] if s["ltl"]]
        result["probes"].append(dict(name="PI consecutive-switch formula gap", snapshots=[previous, incorrect],
            all_eight_ltl_hold=all(r["holds"] for r in checks), verdicts=checks,
            explanation="Both outputs change during a switch to cascade following another switch; prev(normalMode) is false, so S8 does not constrain this transition."))
        mask_formula = next(s["ltl"] for s in new["datasets/selfmade/self-hard-06.json"]["specs"] if s["sid"] == "S13")
        mask_trace = [dict(triplatched=True, latchedcausemask=4), dict(triplatched=True, latchedcausemask=8)]
        v = evaluate(mask_formula, mask_trace, _atom_evaluator({"triplatched": "BOOL", "latchedcausemask": "WORD"}, {}))
        result["probes"].append(dict(name="Numeric mask monotonicity is weaker than bit preservation", formula=mask_formula,
            snapshots=mask_trace, verdict=asdict(v), old_bits_preserved=(8 & 4) == 4,
            explanation="4 -> 8 satisfies >= while losing bit2; S13 alone cannot establish bitwise accumulation."))
    current_ledger = json.loads(ledger_before)
    result["ledger"] = dict(unchanged=ledger.read_bytes() == ledger_before, sha256=sha(ledger_before),
                            spent_cny=current_ledger["spent_cny"], events=len(current_ledger["events"]))
    if not result["ledger"]["unchanged"]:
        raise RuntimeError("Budget ledger changed during read-only audit")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("x", encoding="utf-8", newline="\n") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(json.dumps(dict(out=str(args.out), reference_tasks=len(result["reference_checks"]),
                         passed=sum(r["tests_passed"] for r in result["reference_checks"]),
                         total=sum(r["tests_total"] for r in result["reference_checks"]),
                         interface_failures=[r["pid"] for r in result["reference_checks"] if r["interface_errors"]],
                         dataset_failures=[r["pid"] for r in result["reference_checks"] if r["dataset_errors"]],
                         ledger_unchanged=True), ensure_ascii=False))


if __name__ == "__main__":
    main()

"""Check every supplied reference on actual fixture scans, keeping the run.py group boundaries."""
import argparse
import json
import sys
from collections import Counter, defaultdict
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT.parent
sys.path.insert(0, str(BUNDLE))
from stbench.schema import Problem, TestCase
from stbench.st.interp import Interpreter, _match
from stbench.st.typecheck import check_st
from stbench.st.driver import _plain, check_outputs
from stbench.modelcheck import snapshot, _atom_evaluator
from stbench.ltl import evaluate, parse
from stbench.spec_policy import formula_names
from stbench.spec_observers import observer_for

target = {"public-medium-04","self-hard-02","self-hard-04","self-hard-06",
          "self-hard-07","self-medium-05","self-medium-06"}

def inspect(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    p = Problem.from_dict(data)
    src = (path.parent/"tests"/(p.pid+".reference.st")).read_text(encoding="utf-8")
    parsed = check_st(src)
    cases = defaultdict(list)
    for c in data["test_cases"]:
        mode = c.get("mode") or p.case_mode
        cases[(c.get("group", ""), mode, c["tc_id"] if mode == "single" else "")].append(c)
    nsteps = 0
    ns = {v.name.lower() for v in p.variables}
    observer = observer_for(p.provenance.get("r9_spec_policy", {}).get("observer"))
    if observer:
        ns.update(observer({}, None, True))
    out = []
    for (group, mode, _), seq in cases.items():
        it = Interpreter(parsed.pou, parsed.structs)
        frames, ids = [], []
        for i,c in enumerate(seq):
            for k,v in c.get("init", {}).items():
                it.set_var(k,v)
            if not i:
                initial = deepcopy({k:v for k,v in snapshot(it).items() if k in ns})
                if observer: initial.update(observer(initial, None, True))
            for k,v in c.get("const_inputs", {}).items():
                it.set_var(k,v)
            inputs = {k.lower():v for k,v in c.get("inputs", {}).items()}
            constants = {k.lower() for k in c.get("const_inputs", {})}
            for v in p.inputs:
                key = v.name.lower()
                if key in inputs:
                    it.set_var(key,inputs[key])
                elif key not in constants and it.types.get(key,"").upper()=="BOOL":
                    it.set_var(key,False)
            for _ in range(max(1,c.get("cycles",1))):
                it.scan(c.get("scan_interval_ms"))
                frame = deepcopy({k:v for k,v in snapshot(it).items() if k in ns})
                if observer: frame.update(observer(frame, frames[-1] if frames else initial, False))
                frames.append(frame)
                ids.append(c["tc_id"])
            outcome = check_outputs(it, p, TestCase.from_dict(c), mode)
            assert outcome.passed, (p.pid, c["tc_id"], outcome.message)
            nsteps += 1
        atom = _atom_evaluator(it.types, parsed.structs)
        for s in p.specs:
            if not s.ltl: continue
            row = dict(pid=p.pid,sid=s.sid,first=ids[0],last=ids[-1],group=group)
            try:
                ast = parse(s.ltl)
                row["non_interface_names"] = sorted(formula_names(s.ltl)-ns)
                verdict = evaluate(ast,frames,atom,init_snapshot=initial)
                status = "inconclusive" if verdict.inconclusive else "hold" if verdict.holds else "violated"
                row.update(status=status,reason=verdict.reason)
                if status=="violated":
                    n = verdict.counterexample_at-1
                    row.update(case=ids[n],scan=n+1,formula=s.ltl,
                               previous={k:_plain(v) for k,v in (frames[n-1] if n else initial).items() if k in ns},
                               actual={k:_plain(v) for k,v in frames[n].items() if k in ns})
            except Exception as e:
                row.update(status="error", reason=repr(e))
            out.append(row)
    return nsteps,out

if __name__=="__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "trace_audit.json")
    destination = parser.parse_args().output
    total=0
    results=[]
    for f in sorted(BUNDLE.glob("datasets/*/*-*.json")):
        n,rows=inspect(f)
        total+=n
        results.extend(rows)
    by = Counter(r["status"] for r in results)
    seven = Counter(r["status"] for r in results if r["pid"] in target)
    print("checked cases",total,"trace/formula verdicts",by,"seven",seven)
    for r in results:
        if r["status"] in ("violated","error"):
            print(r["pid"],r["sid"],r.get("case",r["first"]),r["reason"][:90])
    output={"cases":total,"all":by,"seven":seven,"rows":results}
    destination.write_text(json.dumps(output,ensure_ascii=False,indent=2),encoding="utf-8")

    if any(r['status'] != 'hold' or r.get('non_interface_names') for r in results):
        sys.exit(f'Non-passing or unbound formula: see {destination}')

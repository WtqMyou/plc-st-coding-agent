"""Check every supplied reference on actual fixture scans, keeping the run.py group boundaries."""
import json
import sys
from collections import Counter, defaultdict
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BUNDLE = ROOT
sys.path.insert(0, str(BUNDLE))
from stbench.schema import Problem
from stbench.st.interp import Interpreter, _match
from stbench.st.typecheck import check_st
from stbench.st.driver import _plain
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
        mode, _, named_group = mode.partition(":")
        cases[(named_group or c.get("group", ""), mode, c["tc_id"] if mode == "single" else "")].append(c)
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
                it.scan()
                frame = deepcopy({k:v for k,v in snapshot(it).items() if k in ns})
                if observer: frame.update(observer(frame, frames[-1] if frames else initial, False))
                frames.append(frame)
                ids.append(c["tc_id"])
            assert all(_match(it.get_var(k),v) for k,v in c["expected"].items()), (p.pid,c["tc_id"])
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



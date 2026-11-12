"""Explicit BFS of PLC memory × the finite history needed by safety properties.

Every reachable input edge is judged before merging its destination.  An earlier
occurrence of an equal product state has at least as much remaining depth.
Other temporal formulae use bounded path enumeration without state merging.
"""
from collections import defaultdict
from copy import deepcopy
import itertools
import re
import time

from .ltl import evaluate
from .modelcheck import SpecResult, snapshot, _atom_evaluator
from .public_input_contracts import scan_contract
from .st.interp import Interpreter, SimError, SimulationTimeout, ArrayValue, StructValue, VariantValue


def _value_key(value, seen):
    """Retain type, floating representation and within-memory reference sharing."""
    if isinstance(value, bool): return (bool, value)
    if isinstance(value, int): return (int, value)
    if isinstance(value, str): return (str, value)
    if isinstance(value, float): return (float, value.hex())
    if value is None: return (None,)
    oid = id(value)
    if oid in seen: return ("ref", seen[oid])
    seen[oid] = len(seen)
    if isinstance(value, ArrayValue):
        return ("arr", value.lo, value.hi, tuple(_value_key(v, seen) for v in value.items))
    if isinstance(value, StructValue):
        return ("struct", value.type_name, _value_key(value.values, seen))
    if isinstance(value, VariantValue):
        return ("variant", value.tag, _value_key(value.value, seen))
    if isinstance(value, (list, tuple)):
        return (type(value), tuple(_value_key(v, seen) for v in value))
    if isinstance(value, dict):
        return ("dict", tuple((k, _value_key(value[k], seen)) for k in sorted(value)))
    raise TypeError(f"Unsupported state value {type(value).__name__}")


def _mentions(node):
    if node.tok is not None:
        yield node.tok.value.lower()
    for child in (*node.args, *node.stmts, *node.else_body):
        yield from _mentions(child)
    for condition, body in node.elifs:
        yield from _mentions(condition)
        for child in body: yield from _mentions(child)


def _overwritten(pou):
    """Only drop scalar whole-name assignments executed before any possible read.

    Keep an overapproximation at branches/loops. RETURN can skip later writes.
    """
    touched, killed = set(), set()
    for node in pou.body:
        words = set(_mentions(node))
        if "return" in words or any(n.kind == "return" for n in _walk(node)):
            break
        if node.kind == "assign" and node.args[0].kind == "name":
            name = node.args[0].tok.value.lower()
            if name not in touched and name not in _mentions(node.args[1]):
                killed.add(name)
        touched.update(words)
    return killed


def _walk(node):
    yield node
    for child in (*node.args, *node.stmts, *node.else_body):
        yield from _walk(child)
    for condition, body in node.elifs:
        yield from _walk(condition)
        for child in body: yield from _walk(child)


def _monitor(node):
    """Offset of each value potentially observed from the anchor of a G body."""
    seen = []
    offsets = [0]
    def visit(n, offset):
        offsets.append(offset)
        if n.kind not in {"atom","true","false","and","or","impl","iff","not","X","prev"}:
            return False
        if n.kind == "atom":
            names = set(re.findall(r"[^\W\d]\w*", n.text.lower()))
            seen.append((offset, names))
            if re.search(r"\bprev\s*\(", n.text, re.I):
                seen.append((offset-1, names))
                offsets.append(offset-1)
        delta = 1 if n.kind=="X" else -1 if n.kind=="prev" else 0
        return all(visit(c, offset+delta) for c in n.args)
    if node.kind != "G" or not visit(node.args[0],0): return None
    return max(offsets), min(offsets), seen


def explore(rep, res, parsed, space, observer, observer_names, depth_limit, edge_limit, deadline, started):
    it = Interpreter(res.pou, res.structs)
    names = tuple(space.domains)
    input_names = {n for n,s in it.sections.items() if str(s).upper()=="VAR_INPUT"}
    bad = space.validate(input_names)
    if bad or any(not space.domains[n] for n in names):
        rep.error = "Unknown or empty input domain: " + str(bad or names)
        rep.stop_reason = "invalid_input"
        return rep
    fixed = set(n.lower() for n in space.fixed_inputs)
    try:
        allowed, legal_size = scan_contract(rep.program, space.domains)
    except ValueError as exc:
        rep.error, rep.stop_reason = str(exc), "invalid_input"
        return rep
    if allowed is not None:
        rep.input_space_size = legal_size
    rep.fixed_input_domains = {n: list(space.domains[n]) for n in names if n.lower() in fixed}
    ext = set(n.lower() for n in names)
    killed = _overwritten(res.pou)
    persistent = tuple(sorted(n for n in it.mem if n not in ext and
        (n not in killed or not isinstance(it.mem[n], (bool,int,float,str)))))
    initial = snapshot(it)
    if observer: initial.update(observer(initial,None,True))
    all_names = set(initial)
    plans = [_monitor(node) for _,_,node in parsed]
    fast = all(m is not None for m in plans)
    rep.algorithm = "finite_window_product_bfs" if fast else "full_prefix_enumeration"
    history = defaultdict(int)
    boundary_age = 0
    if fast:
        for fut,past,uses in plans:
            boundary_age = max(boundary_age, fut-past)
            for offset, observed_names in uses:
                for name in observed_names & all_names:
                    history[name] = max(history[name], fut-offset)
    # Observer code is allowed to inspect its whole previous frame, including
    # previous physical inputs. Retain it without guessing private dependencies.
    if observer:
        for name in all_names: history[name] = max(history[name],1)
    history = tuple(sorted((name,k) for name,k in history.items() if k))
    ev = _atom_evaluator(it.types, res.structs)
    done = set()
    determinate = set()
    generic_unknown = set()
    visited = set()
    machine_states = set()
    # The initial node uses unconstrained bindings until the first scan.
    layer = [(it.mem.copy(), (), None)]
    rep.stop_reason = "depth_complete"

    def machine_key(mem):
        aliases = {}
        return tuple(_value_key(mem[n],aliases) for n in persistent)

    def product_key(machine, frames, binds):
        suffix = tuple(tuple(_value_key(f[n],{}) for f in frames[-k:]) for n,k in history)
        return machine, binds, min(len(frames),boundary_age), suffix

    def inspect(frames, final):
        depth = len(frames)
        for idx,(sid,formula,node) in enumerate(parsed):
            if sid in done: continue
            if fast:
                horizon = plans[idx][0]
                positions = range(max(1,depth-horizon),depth+1)
                body = node.args[0]
            else:
                positions = range(1,depth+1)
                body = node
            for pos in positions:
                verdict = evaluate(body, frames, ev, start=pos,init_snapshot=initial)
                if verdict.inconclusive:
                    if not fast and final: generic_unknown.add(sid)
                elif not verdict.holds:
                    rep.specs.append(SpecResult(spec_id=sid,formula=formula,holds=False,
                        contradicting=True,counterexample=list(frames),ce_at=verdict.counterexample_at,
                        bounded=False,reason=verdict.reason))
                    done.add(sid)
                    break
                else: determinate.add(sid)

    class Stop(Exception): pass
    primitive=(bool,int,float,str,type(None))
    scalar_mem = all(isinstance(v,primitive) for v in it.mem.values()) and all(
        isinstance(v,primitive) for vals in space.domains.values() for v in vals)
    try:
        for depth in range(1,depth_limit+1):
            rep.current_depth = depth
            nxt = []
            for parent_idx,(mem,frames,bindings) in enumerate(layer):
                axes = [(bindings[i],) if bindings is not None and n.lower() in fixed else space.domains[n]
                        for i,n in enumerate(names)]
                for values in itertools.product(*axes):
                    if deadline is not None and time.monotonic() >= deadline:
                        rep.stop_reason = "time_limit"; rep.truncated=True; raise Stop()
                    if allowed is not None and not allowed(values):
                        continue
                    if rep.edges_checked >= edge_limit:
                        rep.stop_reason = "transition_limit"; rep.truncated=True; raise Stop()
                    # The previous memory is immutable throughout expansion.
                    it.mem = mem.copy() if scalar_mem else deepcopy(mem)
                    for n,v in zip(names,values):
                        it.set_var(n, v if isinstance(v,primitive) else deepcopy(v))
                    it.scan()
                    rep.edges_checked += 1
                    snap = snapshot(it)
                    if observer: snap.update(observer(snap, frames[-1] if frames else initial, False))
                    new_frames = frames + (snap,)
                    inspect(new_frames, depth == depth_limit)
                    machine = machine_key(it.mem)
                    machine_states.add(machine)
                    if depth < depth_limit:
                        fixed_key = tuple(_value_key(v,{}) for n,v in zip(names,values) if n.lower() in fixed)
                        if fast:
                            key = product_key(machine,new_frames,fixed_key)
                            if key in visited: continue
                            visited.add(key)
                        nxt.append((it.mem, new_frames,values if fixed else None))
            rep.completed_depth = depth
            rep.frontier_states = len(nxt)
            if not nxt and depth < depth_limit:
                rep.stop_reason = "reachable_product_closed"
                rep.completed_depth = depth_limit
                break
            layer = nxt
    except Stop:
        rep.frontier_states = len(layer)-parent_idx
    except (SimError,SimulationTimeout,ValueError,KeyError,OverflowError,TypeError) as exc:
        rep.error = f"Scan or property evaluation failed: {type(exc).__name__}: {exc}"
        rep.stop_reason = "evaluation_error"
    rep.traces_explored = rep.edges_checked
    rep.states_explored = len(machine_states)
    rep.product_states = len(visited)
    rep.max_depth = rep.current_depth
    rep.elapsed_seconds = time.monotonic()-started
    for i,(sid,formula,node) in enumerate(parsed):
        if sid in done: continue
        insufficient_horizon = fast and depth_limit <= plans[i][0]
        uncertain = bool(rep.error or rep.truncated or insufficient_horizon or
                         sid not in determinate or sid in generic_unknown)
        rep.specs.append(SpecResult(spec_id=sid, formula=formula, holds=not uncertain,
            inconclusive=uncertain, reason=rep.stop_reason))
    return rep

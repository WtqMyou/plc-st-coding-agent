"""Verify the material FIFO's lengths and payload identities over copy-only opaque data."""

from copy import copy, deepcopy
from itertools import product
import time

from .ltl import evaluate, parse
from .modelcheck import _atom_evaluator, _freeze, snapshot
from .st.interp import Interpreter
from .st.typecheck import check_st

DATA = {"head", "fifo", "pushitem"}
BUTTONS = ("pushen", "popen")
# This certificate intentionally covers exactly the delivered properties. General
# changes, additional history or arithmetic require the ordinary checker.
PREDICATES = {
    "S1": "G((count >= 0 AND count <= 8) AND (full <-> count = 8) AND (empty <-> count = 0))",
    "S2": "G(prev(full) AND rising(pushEn) AND !rising(popEn) -> count = 8)",
    "S3": "G(prev(empty) AND rising(popEn) AND !rising(pushEn) -> count = 0)",
    "S5": "G((empty -> head = 0) AND (NOT empty -> head = fifo[1]))",
}

# One-step origin equalities are invariant under arbitrary relabeling of payloads.
# Specify the allowed formulas here, independently of the candidate JSON file.
pop = "rising(popEn) AND prev(count > 0)"
inc = "rising(pushEn) AND !rising(popEn) AND !prev(count >= 8)"
inc_both = "rising(pushEn) AND rising(popEn) AND !prev(count <> 0)"
dec = "!rising(pushEn) AND rising(popEn) AND prev(count > 0)"
origins = []
for i in range(1, 9):
    origins.append(f"((!({pop}) AND prev(count >= {i})) -> fifo[{i}] = prev(fifo[{i}]))")
    if i < 8:
        origins.append(f"((({pop}) AND prev(count > {i})) -> fifo[{i}] = prev(fifo[{i+1}]))")
EXTENDED_PREDICATES = dict(PREDICATES,
    S6=(f"G((((({inc}) OR ({inc_both})) -> count = prev(count) + 1) AND "
        f"(({dec}) -> count = prev(count) - 1) AND ((!(({inc}) OR ({inc_both}) OR ({dec}))) -> count = prev(count))))"),
    S7="G((rising(pushEn) AND (rising(popEn) OR !prev(count >= 8)) AND count >= 1 AND count <= 8) -> fifo[count] = pushItem)",
    S8="G("+" AND ".join(origins)+")")


def _name(node):
    return node.tok.value.lower() if node.kind == "name" else ""


def _control(n):
    if n.kind in {"bool", "num"}:
        return True
    if n.kind == "name":
        return _name(n) not in DATA
    return n.kind in {"binop", "unop"} and all(_control(c) for c in n.args)


def _slot(n):
    return n.kind == "index" and _name(n.args[0]) == "fifo" and _control(n.args[1])


def _data(n):
    return (
        _slot(n)
        or _name(n) in {"pushitem", "head"}
        or n.kind == "num"
        and n.tok.value == "0"
    )


def _certify(n):
    if n.kind == "nop":
        return True
    if n.kind == "assign":
        target, source = n.args
        if _slot(target) or _name(target) == "head":
            return _data(source)
        return target.kind == "name" and _control(target) and _control(source)
    if n.kind == "if":
        return (
            _control(n.args[0])
            and all(_certify(a) for a in n.stmts + n.else_body)
            and all(
                _control(cond) and all(_certify(a) for a in body)
                for cond, body in n.elifs
            )
        )
    if n.kind == "for":
        return (
            n.tok.value.lower() not in DATA
            and all(_control(a) for a in n.args)
            and all(_certify(a) for a in n.stmts)
        )
    return False


def _key(m):
    # Current + previous button observations are encoded in this nonpayload
    # snapshot; all extra retained controller variables are included as well.
    return tuple((k, _freeze(v)) for k, v in sorted(m.mem.items()) if k not in DATA)


def _verdict(ast, prev, now, atom, first):
    if first:
        return evaluate(ast, [now], atom, init_snapshot=prev)
    return evaluate(ast, [prev, now], atom, start=2, init_snapshot=prev)


def _concrete_witness(compiled, path, values, ast):
    """A failed universal equality may use unreachable pre-state payloads.
    Report only a violation reproducible from actual initial values and legal
    input-domain values. Otherwise the caller must fall back to general search.
    """
    for i in range(len(values)):
        m = Interpreter(compiled.pou, compiled.structs)
        init = deepcopy(snapshot(m))
        frames = []
        steps = []
        for j, buttons in enumerate(path):
            inputs = dict(buttons, pushitem=values[(i + j) % len(values)])
            for k, v in inputs.items():
                m.set_var(k, v)
            m.scan()
            frames.append(deepcopy(snapshot(m)))
            steps.append(inputs)
        verdict = evaluate(
            ast, frames, _atom_evaluator(m.types, compiled.structs), init_snapshot=init
        )
        if not verdict.holds and not verdict.inconclusive:
            at = verdict.counterexample_at
            last = frames[at - 1]
            outputs = {k: last[k] for k in ("count", "full", "empty", "head")}
            outputs["fifo_1"] = last["fifo"].items[0]
            return steps, at, outputs
    return None


def try_check(src, problem, domains, specs):
    """None means proof inapplicable; fall back with all original domains."""
    if (
        problem.pid != "self-hard-03"
        or set(domains) != {*BUTTONS, "pushitem"}
        or problem.mc_fixed_inputs
    ):
        return None
    if any(not vals for vals in domains.values()) or any(
        type(x) is not bool for k in BUTTONS for x in domains[k]
    ):
        return None
    if not all(type(x) is int and -(2**15) <= x < 2**15 for x in domains["pushitem"]):
        return None
    expected = PREDICATES if len(specs) == len(PREDICATES) else EXTENDED_PREDICATES
    if len(specs)!=len(expected) or {k:parse(t) for k,t in specs}!={k:parse(t) for k,t in expected.items()}:
        return None
    if min(problem.mc_max_depth, problem.mc_max_traces) < 1:
        return None
    checked = check_st(src)
    if not checked.ok or checked.pou is None:
        return None
    decls = {d.name.lower(): d for d in checked.pou.decls}
    if (
        set(k for k, d in decls.items() if d.section == "VAR_INPUT")
        != {*BUTTONS, "pushitem"}
        or set(k for k, d in decls.items() if d.section == "VAR_IN_OUT") != {"fifo"}
        or set(k for k, d in decls.items() if d.section == "VAR_OUTPUT")
        != {"head", "count", "empty", "full"}
        or decls["fifo"].data_type.replace(" ", "").upper() != "ARRAY[1..8]OFINT"
        or any(
            decls[k].data_type.upper() != "INT" for k in ("head", "pushitem", "count")
        )
        or any(
            decls[k].data_type.upper() != "BOOL" for k in (*BUTTONS, "full", "empty")
        )
        or any(
            d.init is not None and d.init.kind not in {"num", "bool"}
            for d in decls.values()
        )
        or not all(_certify(n) for n in checked.pou.body)
    ):
        return None
    # Tokens are distinct nonzero INTs. Control can only copy them or write
    # zero, with no data-dependent conditions or computed numeric payloads.
    # Hence equal postscan tokens imply equality for every substitution.
    # Arbitrary pre-state tokens strengthen the induction step.
    machine = Interpreter(checked.pou, checked.structs)
    initial = deepcopy(machine.mem)
    predicates = {sid: parse(t) for sid, t in specs}
    atom = _atom_evaluator(machine.types, machine.structs)
    frontier = [(initial, [])]
    seen = set()
    buttons = [
        dict(zip(BUTTONS, pair)) for pair in product(*(domains[k] for k in BUTTONS))
    ]
    total = depth_complete = 0
    started = time.monotonic()
    stop = ""
    violations = {}
    flagged_full_push = 0
    flagged_empty_pop = 0
    for depth in range(1, problem.mc_max_depth + 1):
        following = []
        for mem, path in frontier:
            previous = {k: v for k, v in mem.items() if k not in DATA}
            for pair in buttons:
                if total >= problem.mc_max_traces:
                    stop = "transition_limit"
                    break
                if (
                    problem.mc_max_seconds
                    and time.monotonic() - started >= problem.mc_max_seconds
                ):
                    stop = "time_limit"
                    break
                m = copy(machine)
                m.mem = deepcopy(mem)
                m.set_var("fifo", list(range(1, 9)))
                m.set_var("head", 9)
                m.set_var("pushitem", 10)
                # Keep the same identity for each old slot in the previous
                # snapshot and at entry to this scan. Its numeric value is an
                # arbitrary tag, with no overlap between slots or the new item.
                previous["fifo"] = deepcopy(m.mem["fifo"])
                for k, v in pair.items():
                    m.set_var(k, v)
                m.scan()
                frame = snapshot(m)
                total += 1
                push_edge = pair["pushen"] and not previous["pushen"]
                pop_edge = pair["popen"] and not previous["popen"]
                flagged_full_push += bool(
                    previous["full"] and push_edge and not pop_edge
                )
                flagged_empty_pop += bool(
                    previous["empty"] and pop_edge and not push_edge
                )
                for sid, ast in predicates.items():
                    if sid in violations:
                        continue
                    result = _verdict(ast, previous, frame, atom, not path)
                    if result.inconclusive:
                        return None
                    if not result.holds:
                        witness = _concrete_witness(
                            checked, path + [pair], domains["pushitem"], ast
                        )
                        if witness is None:
                            return None
                        violations[sid] = dict(
                            id=sid,
                            formula=dict(specs)[sid],
                            at=witness[1],
                            inputs=witness[0],
                            outputs=witness[2],
                            explanation="Concrete path replay from the declared initial state.",
                        )
                key = _key(m)
                if key not in seen:
                    seen.add(key)
                    following.append((m.mem, path + [pair]))
            if stop:
                break
        if stop:
            break
        depth_complete = depth
        frontier = following
        if not frontier:
            stop = "fixpoint"
            break
    return dict(
        strategy="opaque-copy universal equality + exact control BFS",
        states=len(seen) + 1,
        transitions=total,
        completed_depth=depth_complete,
        depth_limit=problem.mc_max_depth,
        stop=stop or "depth_complete",
        truncated=stop in {"time_limit", "transition_limit"},
        elapsed_seconds=round(time.monotonic() - started, 4),
        violations=list(violations.values()),
        payload_domain=list(domains["pushitem"]),
        boolean_product=len(buttons),
        raw_inputs_per_scan=len(buttons) * len(domains["pushitem"]),
        S2_trigger_transitions=flagged_full_push,
        S3_trigger_transitions=flagged_empty_pop,
    )

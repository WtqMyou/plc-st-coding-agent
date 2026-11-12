"""Finite caller instances for the reference FIFO. Never quantify an unbound VARIANT."""

from collections import Counter
from copy import copy, deepcopy
from itertools import product
from math import prod
import time

from .ltl import evaluate, parse
from .modelcheck import _atom_evaluator, _freeze, snapshot
from .spec_policy import formula_names
from .st.frontend import Parser, tokenize
from .st.interp import Interpreter
from .st.typecheck import check_st

PROFILE = "fifo-bound-dint-v1"
PAYLOAD = {"item", "buffer"}
INPUTS = ("enqueue", "dequeue", "reset")


class Unsupported(ValueError):
    """The caller binding or the proof of payload independence does not apply."""


def _named(node, name):
    return node.kind == "name" and node.tok.value.lower() == name


def _control(node):
    """Only scalar control expressions and fixed array-shape queries."""
    if node.kind in {"num", "bool"}:
        return True
    if node.kind == "name":
        return node.tok.value.lower() not in PAYLOAD
    if node.kind in {"binop", "unop"}:
        return all(_control(n) for n in node.args)
    return (
        node.kind == "call"
        and node.tok.value.upper() in {"LOWER_BOUND", "UPPER_BOUND"}
        and len(node.args) == 2
        and _named(node.args[0], "buffer")
        and node.args[1].kind == "num"
        and node.args[1].tok.value == "1"
    )


def _slot(node):
    return (
        node.kind == "index"
        and len(node.args) == 2
        and _named(node.args[0], "buffer")
        and _control(node.args[1])
    )


def _certify_stmt(node):
    if node.kind == "nop":
        return True
    if node.kind == "assign":
        dest, src = node.args
        return (
            (_slot(dest) and _named(src, "item"))
            or (_named(dest, "item") and _slot(src))
            or (dest.kind == "name" and _control(dest) and _control(src))
        )
    if node.kind == "if":
        return (
            _control(node.args[0])
            and all(_certify_stmt(n) for n in node.stmts + node.else_body)
            and all(
                _control(cond) and all(_certify_stmt(n) for n in body)
                for cond, body in node.elifs
            )
        )
    return False


def _property_expr(node, allow_previous):
    if _control(node):
        return True
    if node.kind == "call" and node.tok.value.upper() == "PREV":
        return allow_previous and len(node.args) == 1 and _control(node.args[0])
    return node.kind in {"unop", "binop"} and all(_property_expr(n, allow_previous) for n in node.args)


def _state_formula(node, allow_previous=True):
    if node.kind in {"true", "false"}:
        return True
    if node.kind == "atom":
        tokens, errors = tokenize(node.text)
        if errors:
            return False
        p = Parser(tokens)
        expr = p.parse_expression()
        return p.cur.kind == "eof" and _property_expr(expr,allow_previous)
    if node.kind == "prev":
        return allow_previous and _state_formula(node.args[0], False)
    return node.kind in {"not", "and", "or", "impl", "iff"} and all(
        _state_formula(n, allow_previous) for n in node.args
    )


def _bindings(problem):
    config = problem.provenance.get("mc_caller_bindings", {})
    if config.get("profile") != PROFILE or problem.pid != "public-hard-04":
        raise Unsupported("generic VARIANT requires explicit caller bindings")
    actual = {}
    for c in problem.test_cases:
        inputs = {**c.const_inputs, **c.inputs}
        if inputs.get("enqueue") and inputs.get("dequeue"):
            raise Unsupported("the caller prohibits simultaneous enqueue and dequeue")
        if set(c.init) - PAYLOAD or (set(c.inputs) | set(c.const_inputs)) - {
            *INPUTS,
            "item",
        }:
            raise Unsupported("external writes to controller state are not modeled")
        first = c.group not in actual
        if first != ("buffer" in c.init):
            raise Unsupported("each group must bind buffer once at its first scan")
        if (
            "buffer" in c.inputs
            or "buffer" in c.const_inputs
            or (c.mode or problem.case_mode) != "sequence"
        ):
            raise Unsupported("changing caller bindings inside a run is not modeled")
        if first:
            values = c.init["buffer"]
            if (
                not isinstance(values, list)
                or not values
                or any(type(x) is not int or not -(2**31) <= x < 2**31 for x in values)
            ):
                raise Unsupported(
                    "only the bundled nonempty DINT array fixtures are modeled"
                )
            actual[c.group] = values
        for field in (c.inputs, c.const_inputs, c.init):
            if "item" in field and (
                type(field["item"]) is not int or not -(2**31) <= field["item"] < 2**31
            ):
                raise Unsupported("fixture item is not DINT")
    required = {
        g: {"lower": 1, "capacity": len(v), "element_type": "DINT"}
        for g, v in actual.items()
    }
    if not required or config.get("groups") != required:
        raise Unsupported(
            "declared binding list does not match raw fixture types and capacities"
        )
    return actual


def _key(machine):
    # Every input is reassigned on the next edge. All nonpayload memory is retained.
    return tuple(
        (k, _freeze(v))
        for k, v in sorted(machine.mem.items())
        if k not in (*INPUTS, *PAYLOAD)
    )


def search(source, problem, domains, specs, *, include_conflicting_requests=False):
    """Exact BFS for G(predicates of the current and immediately previous scan).

    Conditions, subscripts and every nonpayload variable are independent of item and
    array contents. The only permitted data accesses are copies between item and an
    array element, with real subscript bounds checked on each concrete scan.
    """
    bindings = _bindings(problem)
    parsed = check_st(source)
    if not parsed.ok or parsed.pou is None:
        raise Unsupported("reference did not pass static checking")
    decls = {d.name.lower(): d for d in parsed.pou.decls}
    if (
        set(domains) != set(INPUTS)
        or any(
            not vs or any(type(v) is not bool for v in vs) for vs in domains.values()
        )
        or {k for k, d in decls.items() if d.section == "VAR_INPUT"} != set(INPUTS)
        or any(decls[k].data_type.upper() != "BOOL" for k in INPUTS)
        or {k for k, d in decls.items() if d.section == "VAR_IN_OUT"} != PAYLOAD
        or any(decls[k].data_type.upper() != "VARIANT" for k in PAYLOAD)
    ):
        raise Unsupported("FIFO caller interface changed")
    if problem.mc_fixed_inputs:
        raise Unsupported(
            "fixed-input specialization is not configured for this profile"
        )
    if any(
        d.init is not None
        and (not _control(d.init) or d.init.kind not in {"num", "bool"})
        for d in decls.values()
    ) or not all(_certify_stmt(n) for n in parsed.pou.body):
        raise Unsupported(
            "cannot erase payload: ST uses payload beyond storage copies/shape or unsupported syntax"
        )
    properties = {}
    public = {v.name.lower() for v in problem.variables}
    for sid, formula in specs:
        ast = parse(formula)
        if (
            ast.kind != "G"
            or not _state_formula(ast.args[0])
            or formula_names(formula) - public
        ):
            raise Unsupported("cannot erase payload/history for formula " + sid)
        properties[sid] = ast
    if not properties:
        raise Unsupported("no executable FIFO formulas")
    alphabet = [
        dict(zip(INPUTS, values))
        for values in product(*(domains[k] for k in INPUTS))
        if include_conflicting_requests or not (values[0] and values[1])
    ]
    if not alphabet or min(problem.mc_max_depth, problem.mc_max_traces) < 1:
        raise Unsupported("empty domain or invalid budget")
    started = time.monotonic()
    total = 0
    reports = []
    violations = {}
    for group, values in bindings.items():
        machine = Interpreter(parsed.pou, parsed.structs)
        machine.set_var("buffer", values)
        machine.set_var("item", 0)
        initial = snapshot(machine)
        # Mark startup separately: temporal prev is false at startup regardless
        # of the initial operand. Embedded prev(count) uses the declared count.
        seen = {("boot",)}
        frontier = [(deepcopy(machine.mem), [])]
        atom = _atom_evaluator(machine.types, parsed.structs)
        complete_depth = transitions = 0
        statuses = Counter()
        stop = ""
        for depth in range(1, problem.mc_max_depth + 1):
            following = []
            for mem, path in frontier:
                parent = copy(machine)
                parent.mem = mem
                previous = snapshot(parent)
                for inputs in alphabet:
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
                    for name, val in inputs.items():
                        m.set_var(name, val)
                    m.scan()
                    snap = snapshot(m)
                    statuses[str(snap["status"])] += 1
                    for sid, ast in properties.items():
                        frames = [previous, snap] if path else [snap]
                        verdict = evaluate(ast.args[0], frames, atom, start=len(frames), init_snapshot=initial)
                        if verdict.inconclusive:
                            raise Unsupported(
                                "state predicate was inconclusive: " + sid
                            )
                        if not verdict.holds and sid not in violations:
                            violations[sid] = {
                                "id": sid,
                                "formula": dict(specs)[sid],
                                "at": depth,
                                "binding": group,
                                "inputs": path + [inputs],
                                "outputs": {
                                    "status": snap["status"],
                                    "elementCount": snap["elementcount"],
                                },
                                "initial_buffer": values,
                                "initial_item": 0,
                                "explanation": "Replay from the stated bound caller with all payloads initially as shown.",
                            }
                    transitions += 1
                    total += 1
                    k = (_key(m), tuple(snap[n] for n in INPUTS))
                    if k not in seen:
                        seen.add(k)
                        following.append((m.mem, path + [inputs]))
                if stop:
                    break
            if stop:
                break
            complete_depth = depth
            frontier = following
            if not frontier:
                stop = "fixpoint"
                break
        reports.append(
            dict(
                group=group,
                element_type="DINT",
                lower=1,
                capacity=len(values),
                concrete_initial_buffer=values,
                unique_states=len(seen),
                transitions=transitions,
                completed_depth=complete_depth,
                stop=stop or "depth_complete",
                seen_output_statuses=dict(statuses),
            )
        )
    truncated = any(b["stop"] in {"transition_limit", "time_limit"} for b in reports)
    return dict(
        strategy=PROFILE,
        scope="DINT callers enumerated in bindings only; arbitrary types/capacities undecided",
        payload_scope="payload-independent for accepted ST subset and tested state predicates",
        boolean_product_size=prod(len(s) for s in domains.values()),
        legal_inputs_per_scan=len(alphabet),
        include_conflicting_requests=include_conflicting_requests,
        elapsed_seconds=round(time.monotonic() - started, 4),
        bindings=reports,
        depth_limit=problem.mc_max_depth,
        transition_limit=problem.mc_max_traces,
        time_limit=problem.mc_max_seconds,
        transitions=total,
        states=sum(b["unique_states"] for b in reports),
        truncated=truncated,
        violations=list(violations.values()),
        properties=list(properties),
    )

"""Finite closure of scalar IF/assignment ST with bounded-past safety monitors."""

from collections import deque
from itertools import product
from time import perf_counter

from .ltl import evaluate, parse
from .modelcheck import _atom_evaluator
from .st.frontend import Parser, tokenize
from .st.interp import Interpreter
from .st.typecheck import check_st


def live_at_entry(statements, inputs, observable):
    """Previous values read before a definite write, on any branch."""
    live = set()

    def reads(expr):
        if expr.kind not in {"name", "bool", "num", "binop", "unop", "call"}:
            raise ValueError("Unsupported scalar expression: " + expr.kind)
        if expr.kind == "call" and expr.tok.value.upper() not in {
            "MAX",
            "MIN",
            "ABS",
            "LIMIT",
        }:
            raise ValueError(
                "Unsupported scalar expression function: " + expr.tok.value
            )
        found = {expr.tok.value.lower()} if expr.kind == "name" else set()
        for child in expr.args:
            found.update(reads(child))
        return found

    def block(nodes, available):
        available = set(available)
        for node in nodes:
            if node.kind == "assign" and node.args[0].kind == "name":
                target, rhs = node.args
                live.update(reads(rhs) - available)
                available.add(target.tok.value.lower())
            elif node.kind == "if":
                arms = [(node.args[0], node.stmts), *node.elifs]
                for condition, _ in arms:
                    live.update(reads(condition) - available)
                arms_after = [block(body, available) for _, body in arms]
                available = set.intersection(
                    block(node.else_body, available), *arms_after
                )
            elif node.kind != "nop":
                raise ValueError("Unsupported scalar closure statement: " + node.kind)
        return available

    written = block(statements, inputs)
    return sorted(live | (observable - written))


def observed_history(specs, declared):
    """For each time offset, identify the variables actually read by the monitor."""
    reads = [set()]
    def ensure(lag):
        while len(reads) <= lag:
            reads.append(set())
    def st(node, lag):
        ensure(lag)
        if node.kind == "name" and node.tok.value.lower() in declared:
            reads[lag].add(node.tok.value.lower())
        past = node.kind == "call" and node.tok.value.upper()=="PREV"
        for child in node.args:
            st(child,lag+int(past))
    def visit(node,lag):
        ensure(lag)
        if node.kind=="atom":
            tokens,errors=tokenize(node.text)
            if errors:
                raise ValueError(f"Malformed monitor atom {node.text}")
            parser=Parser(tokens)
            expr=parser.parse_expression()
            if parser.cur.kind!="eof":
                raise ValueError(f"Incomplete monitor atom {node.text}")
            st(expr,lag)
        elif node.kind in {"and","or","iff","impl","not","prev","true","false"}:
            for child in node.args:
                visit(child,lag+int(node.kind=="prev"))
        else:
            raise ValueError("Expected current/bounded-past G predicate")
    for _,node in specs:
        if node.kind!="G":
            raise ValueError("Expected a global safety formula")
        visit(node.args[0],0)
    return reads[0], [sorted(set.union(*reads[i:])) for i in range(1,len(reads))]


def search(problem, source, domains, edge_limit=2_000_000):
    """Execute every edge of the bounded reachable product. No arithmetic abstraction."""
    if (
        problem.provenance.get("r9_spec_policy", {}).get("observer")
        or problem.mc_fixed_inputs
    ):
        raise ValueError("External observers and fixed inputs are unsupported")
    checked = check_st(source)
    if not checked.ok or not checked.pou or checked.structs:
        raise ValueError("Checkable scalar POU required")
    it = Interpreter(checked.pou, checked.structs)
    if any(type(v) not in (bool, int, float) for v in it.mem.values()):
        raise ValueError("Non-scalar memory")
    if set(domains) != {n for n, v in it.sections.items() if v == "VAR_INPUT"}:
        raise ValueError("Expected complete input declarations")
    specs = [(s.sid, parse(s.ltl)) for s in problem.specs if s.ltl.strip()]
    now, history_keys = observed_history(specs, it.mem)
    # An unwritten output observed only on a later scan still affects the product.
    observable=now.union(*history_keys)
    live = live_at_entry(checked.pou.body, set(domains), observable)
    names = list(domains)
    inputs = list(product(*(domains[k] for k in names)))
    initial = it.mem.copy()
    atom = _atom_evaluator(it.types, checked.structs)
    queue = deque([(initial, (), 0)])
    visited = set()
    states_by_level = {}
    edges = 0
    fail = {}
    start = perf_counter()

    def key(mem, keys):
        return tuple(
            (type(v), v.hex() if type(v) is float else v)
            for v in (mem[k] for k in keys)
        )

    while queue:
        old, trail, depth = queue.popleft()
        states_by_level[depth] = states_by_level.get(depth, 0) + 1
        if depth >= problem.mc_max_depth:
            continue
        for values in inputs:
            if edges >= edge_limit:
                return {
                    "status": "truncated",
                    "edges": edges,
                    "edge_budget": edge_limit,
                    "states": len(visited) + 1,
                }
            it.mem = old.copy()
            for n, v in zip(names, values):
                it.set_var(n, v)
            it.scan()
            edges += 1
            mem = it.mem
            frames = (*trail, mem)
            for sid, node in specs:
                if sid in fail:
                    continue
                res = evaluate(
                    node.args[0], frames, atom, start=len(frames), init_snapshot=initial
                )
                if not res.holds or res.inconclusive:
                    fail[sid] = {
                        "depth": depth + 1,
                        "inputs": dict(zip(names, values)),
                        "previous_memory": old,
                        "current_memory": mem.copy(),
                        "inconclusive": res.inconclusive,
                    }
            # A first-scan monitor can distinguish the initial state, so it
            # has no entry in this set of states reached after at least one scan.
            past = frames[-len(history_keys):] if history_keys else ()
            nodekey = key(mem, live), tuple(key(frame,keys) for frame,keys in zip(reversed(past),history_keys))
            if nodekey not in visited:
                visited.add(nodekey)
                queue.append((mem.copy(), past, depth + 1))
    return {
        "status": "counterexample_or_unknown" if fail else "bounded_pass",
        "sids": [sid for sid, _ in specs],
        "findings": fail,
        "depth": problem.mc_max_depth,
        "inputs_per_state": len(inputs),
        "persistent_at_entry": live,
        "monitor_previous": history_keys[0] if history_keys else [],
        "monitor_history_by_lag": history_keys,
        "edges": edges,
        "edge_budget": edge_limit,
        "states_including_initial": len(visited) + 1,
        "new_states_by_depth": states_by_level,
        "closed_before_depth_bound": max(states_by_level) < problem.mc_max_depth,
        "elapsed_seconds": round(perf_counter() - start, 3),
    }

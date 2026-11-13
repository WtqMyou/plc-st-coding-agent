"""Bounded LTL over named, independently bound ARRAY[*] input/output fixtures."""
from copy import copy, deepcopy
from time import monotonic

from .ltl import evaluate, parse
from .modelcheck import _atom_evaluator, snapshot
from .spec_policy import formula_names
from .st.interp import ArrayValue, Interpreter, SimError, _match
from .st.typecheck import check_st

PROFILE = "analog-open-arrays-v1"
FLAGS = ("__spec_analog_preserve", "__spec_analog_disabled", "__spec_analog_errors", "__spec_analog_conversion")


def observe(current, previous=None, initial=False):
    if initial:
        return dict.fromkeys(FLAGS, True)
    before = previous or {}
    raw = before.get("analogvalues")
    channels = before.get("channels")
    actual = current.get("channels")
    if not all(isinstance(v, ArrayValue) for v in (raw, channels, actual)):
        raise ValueError("Missing bound analog caller arrays")
    count = current.get("count")
    if type(count) is not int or not 0 <= count <= min(len(raw.items), len(channels.items)):
        raise ValueError("Analog count is outside its caller binding")
    if (actual.lo, actual.hi) != (channels.lo, channels.hi):
        return dict.fromkeys(FLAGS, False)
    preserve = raw == current.get("analogvalues")
    disabled_ok = errors_ok = conversion_ok = True
    for i, (old, new) in enumerate(zip(channels.items, actual.items)):
        old = {k.lower():v for k, v in old.values.items()}
        new = {k.lower():v for k, v in new.values.items()}
        preserve &= all(new[k] == v for k, v in old.items() if k not in ("retval", "outputvalue"))
        if i >= count:
            preserve &= new == old
            continue
        if not old["enable"]:
            disabled_ok &= new == old
            continue
        mode, lo, hi = old["measuringmode"], old["lolim"], old["hilim"]
        codes = set()
        if mode not in (0, 1, 2):
            codes.add(0x8001)
        if hi <= lo:
            codes.add(0x8002)
        if codes:
            errors_ok &= new["retval"] in codes and new["outputvalue"] == old["outputvalue"]
            continue
        value = raw.items[i]
        if mode in (1, 2):
            converted = value / (10.0 if mode == 1 else 100.0)
        else:
            fraction = (value + 27648.0) / 55296.0 if old["bipolar"] else value / 27648.0
            converted = lo + fraction * (hi - lo)
        conversion_ok &= _match(new["outputvalue"], converted)
    return dict(zip(FLAGS, (preserve, disabled_ok, errors_ok, conversion_ok)))


def search(source, problem, specs):
    config = problem.provenance.get("mc_caller_bindings", {})
    if config.get("profile") != PROFILE or not config.get("fixtures"):
        raise ValueError("Missing analog caller profiles")
    parsed = check_st(source)
    if not parsed.ok or parsed.pou is None:
        raise ValueError("Analog candidate failed to compile")
    machine = Interpreter(parsed.pou, parsed.structs)
    public = {"count", "analogvalues", "channels"}
    declared = {k:v for k,v in machine.types.items() if k in public}
    if ({k:v.upper() for k,v in declared.items()} != {
            "count":"DINT", "analogvalues":"ARRAY[*] OF INT", "channels":"ARRAY[*] OF ST_ANALOGCHANNEL"}
        or machine.sections["count"] != "VAR_INPUT"
        or any(machine.sections[name] != "VAR_IN_OUT" for name in ("analogvalues", "channels"))
        or any(k.startswith("__spec_") for k in machine.types)):
        raise ValueError("Candidate does not implement the course ARRAY[*] interface or uses a reserved observer name")
    if min(problem.mc_max_depth, problem.mc_max_traces) < 1:
        raise ValueError("Invalid search budget")
    asts = {}
    for sid, formula in specs:
        if formula_names(formula) - public - set(FLAGS):
            raise ValueError("Unknown formula name: " + sid)
        asts[sid] = parse(formula)
    formulas = dict(specs)
    cases = {c.tc_id:c for c in problem.test_cases}
    atom = _atom_evaluator(machine.types, parsed.structs)
    violations = {}
    bindings = []
    edges = 0
    deadline = monotonic() + problem.mc_max_seconds if problem.mc_max_seconds else None
    truncated = False

    def frame(it):
        return deepcopy({k:v for k,v in snapshot(it).items() if k in public})

    for cid in config["fixtures"]:
        fixture = cases[cid]
        it = Interpreter(parsed.pou, parsed.structs)
        for name in ("analogValues", "channels"):
            it.set_var(name, fixture.init[name])
        initial = frame(it)
        initial.update(observe(initial, initial=True))
        raw, channels = initial["analogvalues"], initial["channels"]
        counts = range(min(len(raw.items), len(channels.items)) + 1)
        bindings.append(dict(fixture=cid, raw_bounds=[raw.lo, raw.hi], channel_bounds=[channels.lo, channels.hi],
                             count_domain=list(counts), transitions=0))
        layer = [(it, [], [])]
        for depth in range(1, problem.mc_max_depth + 1):
            following = []
            for parent, frames, inputs in layer:
                for n in counts:
                    if edges >= problem.mc_max_traces or (deadline and monotonic() >= deadline):
                        truncated = True
                        break
                    child = copy(parent)
                    child.mem = deepcopy(parent.mem)
                    child.set_var("count", n)
                    try:
                        child.scan()
                    except SimError as exc:
                        raise ValueError(f"{cid} count={inputs+[n]}: {exc}") from exc
                    current = frame(child)
                    if current["count"] != n:
                        raise ValueError(f"{cid} candidate overwrote count for inputs {inputs+[n]}")
                    current.update(observe(current, frames[-1] if frames else initial))
                    trace = frames + [current]
                    sequence = inputs + [n]
                    edges += 1
                    bindings[-1]["transitions"] += 1
                    for sid, ast in asts.items():
                        if sid in violations:
                            continue
                        verdict = evaluate(ast, trace, atom, init_snapshot=initial)
                        if verdict.inconclusive:
                            raise ValueError(f"{cid} {sid}: finite trace cannot determine property")
                        if not verdict.holds:
                            violations[sid] = dict(id=sid, formula=formulas[sid], fixture=cid,
                                                   inputs=sequence, at=verdict.counterexample_at,
                                                   observer={k:current[k] for k in FLAGS})
                    if depth < problem.mc_max_depth:
                        following.append((child, trace, sequence))
                if truncated:
                    break
            layer = following
            if truncated:
                break
        if truncated:
            break
    return dict(profile=PROFILE, depth=problem.mc_max_depth, bindings=bindings, states=edges+len(bindings),
                transitions=edges, truncated=truncated, violations=list(violations.values()))

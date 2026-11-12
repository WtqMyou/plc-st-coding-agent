"""Sound payload independence for the two numeric-window reference task families.

Only quotient sample magnitudes if the *supplied program and all supplied formulas*
pass the checks below. Arrays, loop bounds, indices and the original ST still run.
"""
import re
from math import isfinite
from .ltl import parse
from .spec_policy import formula_names


def identifiers(n):
    names = {n.tok.value.lower()} if n.kind == "name" else set()
    for c in n.args:
        names |= identifiers(c)
    return names


def statements(nodes):
    for n in nodes:
        yield n
        yield from statements(n.stmts)
        yield from statements(n.else_body)
        for _, branch in n.elifs:
            yield from statements(branch)


def payload_class(p, compiled, domains):
    special = {"public-medium-03":"value", "self-medium-02":"rawvalue"}
    seed = special.get(p.pid)
    if seed not in domains or seed in [n.lower() for n in p.mc_fixed_inputs]:
        return None
    values = domains[seed]
    if len(values)<2 or not all(type(v) in (int,float) and isfinite(v) for v in values):
        return None
    pou = compiled.pou
    decls = {d.name.lower(): d for d in pou.decls}
    if (compiled.structs or any(d.section.upper() == "VAR_IN_OUT" or d.init is not None for d in pou.decls) or
            decls[seed].data_type.upper() not in {"REAL","LREAL"}):
        return None
    nodes = list(statements(pou.body))
    if any(n.kind not in {"assign","if","for"} for n in nodes):
        return None
    assignments = []
    for n in nodes:
        if n.kind != "assign": continue
        lhs,rhs = n.args
        if lhs.kind=="name":
            var, idx = lhs.tok.value.lower(),[]
            if "ARRAY" in decls[var].data_type.upper(): return None
        elif lhs.kind=="index" and lhs.args[0].kind=="name":
            var,idx = lhs.args[0].tok.value.lower(),lhs.args[1:]
        else: return None
        if decls[var].section.upper()=="VAR_INPUT": return None
        assignments.append((var,idx,rhs))
    taint={seed}
    while True:
        new = taint | {var for var,_,rhs in assignments if identifiers(rhs)&taint}
        if taint==new: break
        taint=new
    for name in taint:
        typ=decls[name].data_type.upper()
        if typ not in {"REAL","LREAL"} and not re.fullmatch(r"ARRAY\[[-\d]+\.\.[-\d]+\]\s+OF\s+L?REAL",typ):
            return None
    for node in nodes:
        if node.kind=="assign": continue
        if node.kind=="for" and node.tok.value.lower() in taint: return None
        guards=node.args+[cond for cond,_ in node.elifs]
        if any(identifiers(cond)&taint for cond in guards): return None
    def permitted(rhs):
        if not (identifiers(rhs)&taint):
            return True
        if rhs.kind=="name": return decls[rhs.tok.value.lower()].data_type.upper() in {"REAL","LREAL"}
        if rhs.kind=="index":
            return rhs.args[0].kind=="name" and not any(identifiers(i)&taint for i in rhs.args[1:])
        if rhs.kind=="binop" and rhs.tok.value in {"+","-","*","/"}:
            if rhs.tok.value=="/" and identifiers(rhs.args[1])&taint: return False
            return all(permitted(n) for n in rhs.args)
        return False
    for _,idx,rhs in assignments:
        if any(identifiers(i)&taint for i in idx) or not permitted(rhs): return None
    # In the public task the only observed data-dependent output is average on reset.
    # Verify an unconditional literal-zero write at the end of the top-level true arm.
    def reset_writes_zero():
        last=pou.body[-1]
        if last.kind!="if" or last.args[0].kind!="name" or last.args[0].tok.value.lower()!="reset":
            return False
        if not all(n.kind=="assign" and n.args[0].kind=="name" for n in last.stmts): return False
        writes=[n.args[1] for n in last.stmts if n.args[0].tok.value.lower()=="average"]
        return bool(writes and writes[-1].kind=="num" and float(writes[-1].tok.value)==0.)
    def disabled_holds_output():
        # Both start at zero. Every scan ends with filteredValue := keep;
        # the disable arm cannot write keep. Thus the equality with the
        # immediately preceding output holds for every possible payload.
        if p.pid!="self-medium-02" or len(pou.body)!=2: return False
        branch,copy_out=pou.body
        if branch.kind!="if" or len(branch.args)!=1: return False
        cond=branch.args[0]
        if (cond.kind!="unop" or cond.tok.value.upper()!="NOT" or
            len(cond.args)!=1 or cond.args[0].kind!="name" or cond.args[0].tok.value.lower()!="enable"):
            return False
        if copy_out.kind!="assign" or len(copy_out.args)!=2: return False
        dest,src=copy_out.args
        if any(n.kind!="name" for n in (dest,src)) or dest.tok.value.lower()!="filteredvalue": return False
        keep=src.tok.value.lower()
        if keep not in decls or decls[keep].section.upper()!="VAR" or decls[keep].data_type.upper() not in {"REAL","LREAL"}: return False
        if decls["filteredvalue"].section.upper()!="VAR_OUTPUT" or decls["filteredvalue"].data_type.upper() not in {"REAL","LREAL"}: return False
        return not any(n.kind=="assign" and keep in identifiers(n.args[0]) or
                       n.kind=="for" and n.tok.value.lower()==keep for n in statements(branch.stmts))
    short_means=[
        parse("G((enable AND sampleCount = 1) -> filteredValue = rawValue)"),
        parse("G((enable AND sampleCount = 2) -> filteredValue = (prev(rawValue) + rawValue) / 2.0)")]
    needs_values=False
    for s in p.specs:
        if not s.ltl or not formula_names(s.ltl)&taint: continue
        if p.pid=="self-medium-02" and parse(s.ltl) in short_means:
            needs_values=True
            continue
        if parse(s.ltl)==parse("G(!enable -> filteredValue = prev(filteredValue))") and disabled_holds_output(): continue
        if parse(s.ltl)!=parse("G(reset -> average = 0.0)") or not reset_writes_zero(): return None
    numerical={}
    if needs_values:
        from .window_lineage import prove_samples
        proof=prove_samples(compiled,domains,p.mc_max_depth)
        if not proof:return None
        numerical={"ordered_window_mean":proof}
    return dict(input=seed,taint=sorted(taint),representative=values[0],original_values=list(values),
                justification="Only float data copies/arithmetic; no tainted guard/index/divisor/cast. "
                              "Reset/disable equalities use checked writes. Short means require a complete symbolic enable tree.",
                **numerical)

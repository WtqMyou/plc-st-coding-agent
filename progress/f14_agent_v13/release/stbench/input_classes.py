"""Exact quotient of a finite input set using scalar comparisons in the actual candidate and properties."""
from collections import Counter, defaultdict
from math import isfinite, prod

from .ltl import parse
from .st.frontend import ParseError, Parser, tokenize
from .st.interp import Interpreter, SimError, SimulationTimeout
from .st.typecheck import check_st


def count_combinations(domains):
    return prod(len(values) for values in domains.values())


def threshold_classes(src, problem, domains):
    """Keep one actual input from each class; raw-value uses or unanalysed observers disable merging.

    For an eligible input every occurrence computes a pure comparison with a literal, or it
    is never read. Substituting another member therefore preserves every executed branch,
    memory write, possible runtime error and atomic proposition. This argument applies at
    each scan and also inside temporal operators. It concerns only the given finite domain.
    """
    metadata = dict(original_combinations=count_combinations(domains), classes={})
    def unchanged(reason):
        return domains, dict(original_combinations=count_combinations(domains), classes={},
                             reason=reason, representative_combinations=count_combinations(domains))
    if problem.provenance.get("r9_spec_policy", {}).get("observer"):
        return unchanged("observer reads public inputs")
    parsed = check_st(src)
    if not parsed.ok or parsed.pou is None:
        return unchanged("candidate could not be analysed")
    try:
        machine = Interpreter(parsed.pou, parsed.structs)
        source_tokens, _ = tokenize(src)
        mentions = Counter(str(t.value).lower() for t in source_tokens)
        tests = defaultdict(list)
        def scan(node):
            if node.kind == "binop" and node.tok.value in ("=", "<>", ">", ">=", "<", "<="):
                a,b = node.args
                for var,literal in ((a,b),(b,a)):
                    if var.kind == "name" and literal.kind == "num":
                        tests[var.tok.value.lower()].append(node)
            for child in node.args + node.stmts + node.else_body:
                scan(child)
            for cond, branch in node.elifs:
                scan(cond)
                for child in branch:
                    scan(child)
        for node in parsed.pou.body:
            scan(node)
        for d in parsed.pou.decls:
            if d.init is not None:
                scan(d.init)
        def inspect_formula(node):
            if node.kind == "atom":
                tokens, errors = tokenize(node.text)
                if errors:
                    raise ValueError("unsupported expression")
                mentions.update(str(t.value).lower() for t in tokens)
                parser = Parser(tokens)
                tree = parser.parse_expression()
                if parser.cur.kind != "eof":
                    raise ValueError("unconsumed atom")
                scan(tree)
            for child in node.args:
                inspect_formula(child)
        for spec in problem.specs:
            if spec.ltl:
                inspect_formula(parse(spec.ltl))
        result = dict(domains)
        fixed = {n.lower() for n in problem.mc_fixed_inputs}
        for name, values in domains.items():
            key = name.lower()
            dtype = machine.types.get(key,"").upper()
            if (key in fixed or dtype not in {"BOOL","INT","DINT","LINT","SINT","UINT","UDINT","ULINT",
                                              "USINT","BYTE","WORD","DWORD","LWORD","REAL","LREAL","TIME","LTIME"}
                    or not all(type(v) in (int,float,bool) and isfinite(v) for v in values)):
                continue
            # One extra spelling is the public declaration. Even an unexpected use in a
            # type, member, loop target, unparsed block or atom conservatively rejects it.
            if mentions[key] != 1 + len(tests[key]):
                continue
            groups = {}
            for value in values:
                machine.set_var(name,value)
                signature = tuple(bool(machine.eval(node)) for node in tests[key])
                groups.setdefault(signature, []).append(value)
            if len(groups) < len(values):
                classes = list(groups.values())
                metadata["classes"][name] = classes
                result[name] = [c[0] for c in classes]
        from .window_projection import payload_class
        projection = payload_class(problem,parsed,domains)
        if projection:
            name = projection["input"]
            result[name] = [projection["representative"]]
            metadata["classes"][name] = [projection["original_values"]]
            metadata["window_payload_independence"] = projection
        metadata["representative_combinations"] = count_combinations(result)
        return result,metadata
    except (ValueError, TypeError, AttributeError, ArithmeticError, RuntimeError, KeyError,
            ParseError, SimError, SimulationTimeout):
        return unchanged("analysis unavailable; retained all input values")

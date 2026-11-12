"""Compile the supported scalar ST fragment into replayable SMT-LIB bounded counterexample queries.

The program comes from STBench's checked AST; guards are symbolic and assignments
are sequential. A SAT result here is a candidate counterexample, never a passing
certificate. Unsupported semantics fail closed. The optional Z3 CLI/shared
library is needed only to solve a query, not to inspect/reproduce it.
"""

from dataclasses import dataclass
from fractions import Fraction
from math import prod
from pathlib import Path
import ctypes
import ctypes.util
import os
import shutil
import subprocess

from .ltl import parse
from .st.driver import _collect_domains
from .st.frontend import Parser, tokenize
from .st.interp import Interpreter, _INT_TYPES
from .st.typecheck import check_st


class Unsupported(ValueError):
    pass


@dataclass(frozen=True)
class Term:
    text: str
    sort: str
    lo: Fraction
    hi: Fraction
    den: int = 1  # Common power-of-two denominator of every possible exact value.


def num(n):
    n = Fraction(n)
    v = str(abs(n.numerator))
    if n.denominator != 1:
        v = f"(/ {v}.0 {n.denominator}.0)"
    return f"(- {v})" if n < 0 else v


def literal(v):
    if isinstance(v, bool):
        return Term(str(v).lower(), "Bool", int(v), int(v))
    if not isinstance(v, (int, float)):
        raise Unsupported("non-scalar literal")
    q = Fraction(v)
    return Term(num(q), "Real" if isinstance(v, float) else "Int", q, q, q.denominator)


class Encoder:
    def __init__(self):
        self.lines = ["(declare-fun rnd64 (Real) Real)"]
        self.cache = {}
        self.traps = []
        self.atom_cache = {}
        self.bit_sources = {}
        self.bits = {}
        self.approx = False

    def bit(self, value, index):
        """Keep Boolean circuits for masks through IF, OR and constant writes."""
        key = value.text, index
        if key in self.bits:
            return self.bits[key]
        if value.lo == value.hi:
            answer = literal(bool((int(value.lo) >> index) & 1))
        elif value.lo >= 0 and value.hi < 2**index:
            answer = literal(False)
        elif value.text in self.bit_sources:
            op, *args = self.bit_sources[value.text]
            if op == "ite":
                cond, left, right = args
                answer = self.ite(cond, self.bit(left, index), self.bit(right, index))
            else:
                left, right = args
                answer = self.pair(op, self.bit(left, index), self.bit(right, index))
        else:
            answer = self.boolean(f"(= (mod (div {value.text} {2**index}) 2) 1)")
        self.bits[key] = answer
        return answer

    def expression(self, text, sort, lo, hi, den=1):
        key = (text, sort)
        if key not in self.cache:
            name = f"n{len(self.cache)}"
            self.lines += [
                f"(declare-const {name} {sort})",
                f"(assert (= {name} {text}))",
            ]
            self.cache[key] = name
        return Term(self.cache[key], sort, lo, hi, den)

    def boolean(self, text):
        return self.expression(text, "Bool", 0, 1)

    def neg(self, t):
        if t.sort != "Bool":
            raise Unsupported("non-Boolean negation")
        return self.boolean(f"(not {t.text})")

    def pair(self, op, a, b):
        if op in ("and", "or", "xor", "=>"):
            if a.sort != "Bool" or b.sort != "Bool":
                raise Unsupported("non-Boolean connective")
            return self.boolean(f"({op} {a.text} {b.text})")
        if op in ("=", "distinct", "<", "<=", ">", ">="):
            if (a.sort == "Bool") != (b.sort == "Bool"):
                raise Unsupported("mixed bool comparison")
            if (
                op in ("=", "distinct")
                and a.sort == b.sort == "Int"
                and a.text in self.bit_sources
                and b.lo == b.hi
                and min(a.lo, b.lo) >= 0
                and max(a.hi, b.hi) < 16
            ):
                bits = [self.bit(a, i) for i in range(4)]
                checks = [
                    bit.text if (int(b.lo) >> i) & 1 else f"(not {bit.text})"
                    for i, bit in enumerate(bits)
                ]
                eq = self.boolean(f"(and {' '.join(checks)})")
                return eq if op == "=" else self.neg(eq)
            return self.boolean(f"({op} {a.text} {b.text})")
        if a.sort == "Bool" or b.sort == "Bool":
            raise Unsupported("mixed bool arithmetic")
        sort = "Real" if "Real" in (a.sort, b.sort) else "Int"
        if sort == "Real" and any(
            v.sort == "Int" and max(abs(v.lo), abs(v.hi)) > 2**53 for v in (a, b)
        ):
            raise Unsupported("inexact integer widening")
        den = max(a.den, b.den) if a.den and b.den else 0
        if op == "+":
            lo, hi = a.lo + b.lo, a.hi + b.hi
        elif op == "-":
            lo, hi = a.lo - b.hi, a.hi - b.lo
        elif op == "*":
            values = [x * y for x in (a.lo, a.hi) for y in (b.lo, b.hi)]
            lo, hi = min(values), max(values)
            den = a.den * b.den
        elif op == "/" and sort == "Real" and b.lo == b.hi and b.lo != 0:
            bounds = [a.lo / b.lo, a.hi / b.lo]
            lo, hi = min(bounds), max(bounds)
            den = 0  # Apply the binary64 roundoff envelope to division.
        else:
            raise Unsupported("numeric operator " + op)
        # Over-approximating both magnitude and denominator proves all IEEE
        # binary64 operations are exact (normal or zero). Reject other cases.
        if sort == "Real" and (
            den == 0 or max(abs(lo), abs(hi)) * den > 2**53 or den > 2**1022
        ):
            # Over-approximate finite binary64 round-to-nearest using the same
            # uninterpreted rounding operation for equal exact real operands.
            # The inequalities bound roundoff (subnormals included), not data.
            mag = max(abs(lo), abs(hi))
            if mag >= 2**1023:
                raise Unsupported("possible non-finite arithmetic")
            error = max(mag, 1) * Fraction(1, 2**52)
            exact = self.expression(f"({op} {a.text} {b.text})", "Real", lo, hi, 0)
            rounded = self.expression(
                f"(rnd64 {exact.text})", "Real", lo - error, hi + error, 0
            )
            self.lines.append(
                f"(assert (<= (- {exact.text} {num(error)}) {rounded.text} (+ {exact.text} {num(error)})))"
            )
            self.approx = True
            return rounded
        return self.expression(f"({op} {a.text} {b.text})", sort, lo, hi, den)

    def ite(self, c, a, b):
        if c.sort != "Bool" or a.sort != b.sort:
            raise Unsupported("unsupported conditional types")
        if a == b:
            return a
        result = self.expression(
            f"(ite {c.text} {a.text} {b.text})",
            a.sort,
            min(a.lo, b.lo),
            max(a.hi, b.hi),
            max(a.den, b.den) if a.den and b.den else 0,
        )
        if a.sort == "Int" and result.lo >= 0 and result.hi < 16:
            self.bit_sources[result.text] = ("ite", c, a, b)
        return result

    def cast(self, v, dtype):
        if dtype == "BOOL" and v.sort == "Bool":
            return v
        if dtype in ("REAL", "LREAL") and v.sort in ("Int", "Real"):
            if v.sort == "Real":
                return v
            if max(abs(v.lo), abs(v.hi)) > 2**53:
                raise Unsupported("rounding on integer conversion")
            return self.expression(f"(to_real {v.text})", "Real", v.lo, v.hi, v.den)
        if dtype in _INT_TYPES and v.sort == "Int":
            bits, signed = _INT_TYPES[dtype]
            mod = 2**bits
            lo = -mod // 2 if signed else 0
            hi = lo + mod - 1
            if lo <= v.lo and v.hi <= hi:
                return v
            return self.expression(
                f"(+ {num(lo)} (mod (- {v.text} {num(lo)}) {mod}))", "Int", lo, hi
            )
        if dtype in ("TIME", "LTIME") and v.sort == "Int":
            return v
        raise Unsupported("assignment to " + dtype + " from " + v.sort)

    def expr(self, node, env, previous=None):
        k = node.kind
        op = node.tok.value.upper() if node.tok else ""
        if k == "name":
            name = op.lower()
            if name not in env:
                raise Unsupported("unknown identifier " + name)
            return env[name]
        if k == "bool":
            return literal(op == "TRUE")
        if k == "num":
            if node.tok.literal_type:
                raise Unsupported("typed literal")
            return literal(node.tok.num)
        if (
            k == "call"
            and op == "PREV"
            and len(node.args) == 1
            and previous is not None
        ):
            return self.expr(node.args[0], previous)
        if k == "call" and op == "LIMIT" and len(node.args) == 3:
            lo, value, hi = [self.expr(x, env, previous) for x in node.args]
            inner = self.ite(self.pair("<=", value, hi), value, hi)
            return self.ite(self.pair(">=", lo, inner), lo, inner)
        if k == "unop":
            a = self.expr(node.args[0], env, previous)
            if op == "NOT":
                return self.neg(a)
            if op == "-":
                return self.pair("-", literal(0), a)
            if op == "+":
                return a
        if k == "binop":
            a, b = [self.expr(x, env, previous) for x in node.args]
            if op in ("AND", "OR", "XOR") and a.sort == b.sort == "Int":
                if min(a.lo, b.lo) < 0 or max(a.hi, b.hi) > 65535:
                    raise Unsupported("large/negative bitwise")
                bits = max(1, int(max(a.hi, b.hi)).bit_length())
                if bits <= 8:
                    pieces = [
                        f"(ite ({op.lower()} {self.bit(a,i).text} {self.bit(b,i).text}) {2**i} 0)"
                        for i in range(bits)
                    ]
                    result = self.expression(
                        f"(+ {' '.join(pieces)})", "Int", 0, 2**bits - 1
                    )
                    self.bit_sources[result.text] = (op.lower(), a, b)
                    return result
                shape = f"(bv{op.lower()} ((_ int2bv {bits}) {a.text}) ((_ int2bv {bits}) {b.text}))"
                return self.expression(f"(bv2int {shape})", "Int", 0, 2**bits - 1)
            return self.pair(
                {"<>": "distinct", "AND": "and", "OR": "or", "XOR": "xor"}.get(op, op),
                a,
                b,
            )
        raise Unsupported("expression " + k + " " + op)

    def block(self, stmts, env, path):
        env = dict(env)
        for st in stmts:
            k = st.kind
            if k == "nop":
                continue
            if k == "assign" and st.args[0].kind == "name":
                name = st.args[0].tok.value.lower()
                env[name] = self.cast(self.expr(st.args[1], env), self.types[name])
            elif k in ("if", "case"):
                if k == "if":
                    arms = [(self.expr(st.args[0], env), st.stmts)]
                    arms += [(self.expr(c, env), b) for c, b in st.elifs]
                else:
                    sel = self.expr(st.args[0], env)
                    arms = []
                    for label, body in st.elifs:
                        match = literal(False)
                        for val in label.args:
                            if val.kind != "num":
                                raise Unsupported("nonliteral CASE label")
                            match = self.pair(
                                "or", match, self.pair("=", sel, self.expr(val, env))
                            )
                        arms.append((match, body))
                pending = path
                branches = []
                for cond, body in arms:
                    branches.append(
                        (cond, self.block(body, env, self.pair("and", pending, cond)))
                    )
                    pending = self.pair("and", pending, self.neg(cond))
                merged = self.block(st.else_body, env, pending)
                for cond, branch in reversed(branches):
                    merged = {n: self.ite(cond, branch[n], merged[n]) for n in env}
                env = merged
            elif k == "while":
                active = literal(True)
                for _ in range(8):
                    active = self.pair("and", active, self.expr(st.args[0], env))
                    step = self.block(st.stmts, env, self.pair("and", path, active))
                    env = {n: self.ite(active, step[n], env[n]) for n in env}
                # The same UNSAT query must prove termination after <=8 iterations
                # on every reachable path. A limited unfolding alone is insufficient.
                self.traps.append(
                    self.pair(
                        "and",
                        path,
                        self.pair("and", active, self.expr(st.args[0], env)),
                    )
                )
            else:
                raise Unsupported("statement " + k)
        return env

    def predicate(self, node, time):
        k = node.kind
        if k == "atom":
            if node.text not in self.atom_cache:
                ts, ds = tokenize(node.text)
                if ds:
                    raise Unsupported("invalid atom")
                p = Parser(ts)
                n = p.parse_expression()
                if p.cur.kind != "eof":
                    raise Unsupported("partially parsed atom")
                self.atom_cache[node.text] = n
            return self.expr(
                self.atom_cache[node.text],
                self.frames[time],
                self.frames[max(0, time - 1)],
            )
        if k in ("true", "false"):
            return literal(k == "true")
        if k == "prev":
            return (
                self.predicate(node.args[0], time - 1) if time > 1 else literal(False)
            )
        if k == "X":
            return self.predicate(node.args[0], time + 1)
        if k == "not":
            return self.neg(self.predicate(node.args[0], time))
        if k in ("and", "or", "impl", "iff"):
            a, b = [self.predicate(x, time) for x in node.args]
            return self.pair({"impl": "=>", "iff": "="}.get(k, k), a, b)
        raise Unsupported("temporal operator " + k)

    def build(self, problem, source, depth=None):
        compiled = check_st(source)
        if not compiled.ok or not compiled.pou:
            raise Unsupported("static check failed")
        pou = compiled.pou
        if compiled.structs:
            raise Unsupported("non-scalar definitions")
        if problem.provenance.get("r9_spec_policy", {}).get("observer"):
            raise Unsupported("external observer")
        self.types = {d.name.lower(): d.data_type.upper() for d in pou.decls}
        if not all(
            t in {"BOOL", "REAL", "LREAL", "TIME", "LTIME"} | set(_INT_TYPES)
            for t in self.types.values()
        ):
            raise Unsupported("non-scalar variable")
        if len(self.types) != len(pou.decls):
            raise Unsupported("duplicate declarations")
        domains = _collect_domains(problem)
        input_decls = {d.name.lower() for d in pou.decls if d.section == "VAR_INPUT"}
        if not domains or set(domains) - input_decls:
            raise Unsupported("invalid input domain")

        # Count AST operations generously across all alternatives. The SMT
        # query also checks that no applicable WHILE needs a ninth iteration.
        def cost(node):
            body = sum(cost(x) for x in node.stmts)
            args = sum(cost(x) for x in node.args)
            arms = sum(
                cost(c) + sum(cost(x) for x in branch) for c, branch in node.elifs
            )
            rest = sum(cost(x) for x in node.else_body)
            return 1 + (9 if node.kind == "while" else 1) * (args + body) + arms + rest

        if (
            sum(cost(st) for st in pou.body) > Interpreter.MAX_STEPS_PER_CYCLE
            or Interpreter.MAX_LOOP_ITER < 8
        ):
            raise Unsupported("interpreter per-scan budget")
        q = {s.sid: parse(s.ltl) for s in problem.specs if s.ltl.strip()}
        if len(q) != sum(bool(s.ltl.strip()) for s in problem.specs):
            raise Unsupported("duplicate specification identifier")
        if not q or any(n.kind != "G" for n in q.values()):
            raise Unsupported("requires G(predicate)")
        initial = Interpreter(pou, compiled.structs)
        self.frames = [{n: literal(v) for n, v in initial.mem.items()}]
        self.input_names = {}
        first_input = {}
        fixed = {s.lower() for s in problem.mc_fixed_inputs}
        if not fixed <= set(domains):
            raise Unsupported("fixed input missing from domain")
        steps = problem.mc_max_depth if depth is None else depth
        if type(steps) is not int or steps < 1:
            raise Unsupported("invalid scan horizon")

        def lookahead(node):
            return int(node.kind == "X") + max(
                (lookahead(x) for x in node.args), default=0
            )

        self.lookahead = max(lookahead(s) for s in q.values())
        for t in range(1, steps + self.lookahead + 1):
            env = dict(self.frames[-1])
            for i, (n, values) in enumerate(domains.items()):
                if not values:
                    raise Unsupported("empty input set")
                vlist = [self.cast(literal(v), self.types[n]) for v in values]
                if n in fixed and t > 1:
                    env[n] = first_input[n]
                    continue
                sort = vlist[0].sort
                if any(v.sort != sort for v in vlist):
                    raise Unsupported("heterogeneous domain")
                var = f"in_{t}_{i}"
                self.lines.append(f"(declare-const {var} {sort})")
                choices = " ".join(f"(= {var} {v.text})" for v in vlist)
                self.lines.append(f"(assert (or {choices}))")
                env[n] = Term(
                    var,
                    sort,
                    min(v.lo for v in vlist),
                    max(v.hi for v in vlist),
                    max(v.den for v in vlist),
                )
                if t == 1:
                    first_input[n] = env[n]
                self.input_names[(n, t)] = var
            self.frames.append(self.block(pou.body, env, literal(True)))
        bad = list(self.traps)
        for t in range(1, steps + 1):
            for prop in q.values():
                bad.append(self.neg(self.predicate(prop.args[0], t)))
        bad_text = " ".join(x.text for x in bad)
        return "\n".join(
            [
                f"; {problem.pid}; {steps} scans; input domain size {prod(map(len,domains.values()))} per scan",
                "; Any violated property or incompletely unrolled loop makes this query satisfiable.",
                *self.lines,
                f"(assert (or {bad_text}))",
                "(check-sat)",
                "",
            ]
        )


def solve(query, timeout_ms=20000):
    text = f"(set-option :timeout {timeout_ms})\n" + query
    exe = shutil.which("z3")
    if exe:
        result = subprocess.run(
            [exe, "-in", "-smt2"],
            input=text,
            text=True,
            capture_output=True,
            timeout=timeout_ms / 1000 + 30,
        )
        if result.returncode:
            raise RuntimeError(result.stderr or result.stdout)
        return result.stdout.strip()
    candidates = [os.environ.get("STBENCH_Z3_LIBRARY"), ctypes.util.find_library("z3")]
    if os.name == "nt":
        candidates.extend(
            str(p)
            for p in sorted(
                Path(os.environ.get("ProgramFiles", "C:/Program Files")).glob(
                    "MATLAB/*/bin/win64/libz3.dll"
                ),
                reverse=True,
            )
        )
    path = next((p for p in candidates if p), None)
    if not path:
        raise FileNotFoundError("Install Z3 CLI or set STBENCH_Z3_LIBRARY")
    lib = ctypes.CDLL(path)
    ptr = ctypes.c_void_p
    string = ctypes.c_char_p

    def fn(name, rt, args):
        f = getattr(lib, name)
        f.restype = rt
        f.argtypes = args
        return f

    cfg = fn("Z3_mk_config", ptr, [])()
    ctx = fn("Z3_mk_context", ptr, [ptr])(cfg)
    # Do not let a parser error in an unsupported dialect terminate Python.
    handler_type = ctypes.CFUNCTYPE(None, ptr, ctypes.c_int)
    errors = []
    handler = handler_type(lambda context, code: errors.append(code))
    fn("Z3_set_error_handler", None, [ptr, handler_type])(ctx, handler)
    try:
        answer = fn("Z3_eval_smtlib2_string", string, [ptr, string])(ctx, text.encode())
        result = answer.decode().strip() if answer else ""
        if errors or result not in ("sat", "unsat", "unknown"):
            raise RuntimeError(result[:500])
        return result
    finally:
        fn("Z3_del_context", None, [ptr])(ctx)
        fn("Z3_del_config", None, [ptr])(cfg)

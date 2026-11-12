"""SMT encoding for fixed-shape arrays, records and constant-count FOR loops.

Only scalar leaves may be copied or written by the ST program. Concrete
structured inputs are selected as a whole by a single selector per input.
"""
from math import prod

from .ltl import parse
from .reference_certificates import Encoder, Unsupported, literal
from .st.driver import _collect_domains
from .st.interp import Interpreter, ArrayValue, StructValue, _elem_type
from .st.typecheck import check_st


def leaves(name, value, dtype, structs):
    if isinstance(value, ArrayValue):
        for i, item in enumerate(value.items, value.lo):
            yield from leaves(f'{name}[{i}]', item, _elem_type(dtype, structs), structs)
    elif isinstance(value, StructValue):
        for field, item in value.values.items():
            yield from leaves(name+'.'+field.lower(), item, structs[value.type_name].fields[field], structs)
    else:
        yield name, value, dtype.upper()


def static_number(node):
    if node.kind == 'num' and isinstance(node.tok.num, int):
        return node.tok.num
    if node.kind == 'unop' and node.tok.value == '-':
        return -static_number(node.args[0])
    raise Unsupported('FOR requires literal bounds/step')


def loop_values(node):
    bounds = [static_number(x) for x in node.args]
    start, end = bounds[:2]
    step = bounds[2] if len(bounds) == 3 else 1
    if not step:
        raise Unsupported('zero FOR step')
    seq = range(start, end + (1 if step > 0 else -1), step)
    if len(seq) > Interpreter.MAX_LOOP_ITER:
        raise Unsupported('FOR may exceed interpreter limit')
    return seq


def operation_bound(node):
    total = 4 + sum(operation_bound(c) for c in node.args)
    mult = len(loop_values(node)) if node.kind == 'for' else 1
    if node.kind in {'while', 'repeat', 'exit', 'return'}:
        raise Unsupported('unsupported control flow '+node.kind)
    total += mult * sum(operation_bound(c) for c in node.stmts)
    total += sum(operation_bound(c) for c in node.else_body)
    return total + sum(operation_bound(test)+sum(operation_bound(c) for c in body)
                       for test, body in node.elifs)


class StructuredEncoder(Encoder):
    def choices(self, node, env):
        """Resolve lvalue/read reference to feasible (guard, leaf) pairs."""
        if node.kind == 'name':
            return [(literal(True), node.tok.value.lower())]
        if node.kind == 'member':
            return [(cond, key+'.'+node.tok.value.lower()) for cond,key in self.choices(node.args[0], env)]
        if node.kind != 'index' or node.args[0].kind != 'name':
            raise Unsupported('unsupported structured access')
        name = node.args[0].tok.value.lower()
        arr = self.interp.mem[name]
        if not isinstance(arr, ArrayValue):
            raise Unsupported('indexed non-array')
        idx = self.expr(node.args[1], env)
        if idx.sort != 'Int':
            raise Unsupported('non-integral index')
        if idx.lo < arr.lo or idx.hi > arr.hi:
            outside = self.pair('or', self.pair('<',idx,literal(arr.lo)), self.pair('>',idx,literal(arr.hi)))
            self.traps.append(self.pair('and', self.path, outside))
        if idx.lo == idx.hi and arr.lo <= idx.lo <= arr.hi:
            return [(literal(True), f'{name}[{int(idx.lo)}]')]
        return [(self.pair('=',idx,literal(i)), f'{name}[{i}]') for i in range(arr.lo,arr.hi+1)]

    def expr(self, node, env, previous=None):
        if node.kind in {'index', 'member'}:
            opts = self.choices(node,env)
            val = env[opts[-1][1]]
            for cond, key in reversed(opts[:-1]):
                val = self.ite(cond,env[key],val)
            return val
        return super().expr(node, env, previous)

    def block(self, stmts, env, path):
        env = dict(env)
        for st in stmts:
            self.path = path
            if st.kind == 'for':
                key = st.tok.value.lower()
                for i in loop_values(st):
                    env[key] = self.cast(literal(i),self.types[key])
                    env = self.block(st.stmts,env,path)
            elif st.kind == 'assign' and st.args[0].kind in {'member','index'}:
                result = self.expr(st.args[1],env)
                for cond,key in self.choices(st.args[0],env):
                    val = self.cast(result,self.types[key])
                    env[key] = val if cond.text == 'true' else self.ite(cond,val,env[key])
            else:
                env = super().block([st],env,path)
        self.path = path
        return env

    def input(self, name, values, t, env):
        var = f'input_{t}_{name}'
        self.lines.extend([f'(declare-const {var} Int)', f'(assert (and (<= 0 {var}) (< {var} {len(values)})))'])
        options = []
        for raw in values:
            self.interp.set_var(name, raw)
            flat = leaves(name,self.interp.mem[name],self.interp.types[name],self.interp.structs)
            options.append({k:literal(v) for k,v,_ in flat})
        for key in options[0]:
            val = options[-1][key]
            for i in reversed(range(len(options)-1)):
                match = self.boolean(f'(= {var} {i})')
                val = self.ite(match,options[i][key],val)
            env[key] = val

    def build(self, p, source):
        c = check_st(source)
        if not c.ok or not c.pou:
            raise Unsupported('failed static check')
        self.interp = Interpreter(c.pou,c.structs)
        if any(d.init is not None for d in c.pou.decls):
            raise Unsupported('explicit initializer')
        if p.provenance.get('r9_spec_policy',{}).get('observer') or p.mc_fixed_inputs:
            raise Unsupported('observer/fixed inputs')
        if sum(operation_bound(s) for s in c.pou.body) > Interpreter.MAX_STEPS_PER_CYCLE:
            raise Unsupported('may exceed per-scan operation budget')
        flat = [item for n,v in self.interp.mem.items()
                for item in leaves(n,v,self.interp.types[n],self.interp.structs)]
        self.types = {n:ty for n,_,ty in flat}
        self.frames = [{n:literal(v) for n,v,_ in flat}]
        self.path = literal(True)
        props = {s.sid:parse(s.ltl) for s in p.specs if s.ltl.strip()}
        if not props or any(n.kind!='G' for n in props.values()):
            raise Unsupported('expected G safety properties')
        def temporal(n):
            return n.kind in ('G','U','F','R','X') or any(temporal(x) for x in n.args)
        if any(temporal(prop.args[0]) for prop in props.values()):
            raise Unsupported('unhandled temporal horizon')
        domains = _collect_domains(p)
        if any(not vs or self.interp.sections.get(n)!='VAR_INPUT' for n,vs in domains.items()):
            raise Unsupported('invalid input domain')
        bad = []
        steps = p.mc_max_depth
        for depth in range(steps):
            env = self.frames[-1].copy()
            for name,values in domains.items():
                self.input(name,values,depth+1,env)
            self.frames.append(self.block(c.pou.body,env,literal(True)))
            t=len(self.frames)-1
            for prop in props.values():
                bad.append(self.neg(self.predicate(prop.args[0],t)))
        bad.extend(self.traps)
        return '\n'.join([f'; {p.pid}, original combinations per scan {prod(map(len,domains.values()))}',
                         *self.lines, '(assert (or '+' '.join(x.text for x in bad)+'))','(check-sat)',''])

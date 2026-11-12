"""Certify a short numeric-window trace family from the parsed candidate's actual scans."""
from copy import copy, deepcopy
from dataclasses import dataclass
from math import isfinite

from .st.interp import Interpreter


@dataclass(frozen=True)
class SampleExpression:
    """Rounded binary64 division of an exact integer sum by a positive integer."""
    samples: tuple[int, ...] = ()
    constant: int = 0
    divisor: int = 1

    def __bool__(self):
        raise ValueError("A symbolic sample must not select control flow")


def integer(value):
    if type(value) not in (int,float) or not isfinite(value) or int(value)!=value:
        raise ValueError("Window proof requires integral operands")
    return int(value)


def expression(value):
    return value if isinstance(value,SampleExpression) else SampleExpression(constant=integer(value))


class WindowInterpreter(Interpreter):
    """Reuse ST control, loop, bounds and assignment semantics. Intercept only symbolic REALs."""
    def _cast(self,value,dtype):
        if not isinstance(value,SampleExpression):
            return super()._cast(value,dtype)
        if dtype.upper() not in ("REAL","LREAL"):
            raise ValueError("Symbolic sample converted to a discrete type")
        return value

    def _binop(self,op,left,right,line):
        if not any(isinstance(v,SampleExpression) for v in (left,right)):
            return super()._binop(op,left,right,line)
        a=expression(left)
        if op=="+":
            b=expression(right)
            if a.divisor!=1 or b.divisor!=1:
                raise ValueError("Cannot rearrange a previously rounded value")
            terms=tuple(sorted(a.samples+b.samples))
            constant=a.constant+b.constant
            if len(terms)*self.max_magnitude+abs(constant)>2**53:
                raise ValueError("Integer window sum may lose binary64 precision")
            return SampleExpression(terms,constant)
        if op=="/" and not isinstance(right,SampleExpression) and a.divisor==1:
            divisor=integer(right)
            if not 1<=divisor<=2**53:raise ValueError("Unsupported window divisor")
            return SampleExpression(a.samples,a.constant,divisor)
        raise ValueError(f"Unsupported symbolic window operation {op}")


def prove_samples(compiled,domains,depth):
    """One fresh symbol per scan denotes any declared sample at that position.

    Enumerate the enable tree without merging states. Require exact equality
    of the observed sum's origins, divisor, count, and full flag on every edge.
    Reject if the candidate escapes the arithmetic fragment. The calling taint
    check excludes any sample-dependent address, guard, function or loop bound.
    """
    if not 1<=depth<=12 or set(domains)!={"rawvalue","enable"}:return None
    if not domains["enable"] or any(type(v)!=bool for v in domains["enable"]):return None
    machine=WindowInterpreter(compiled.pou,compiled.structs)
    if {k for k,s in machine.sections.items() if s.upper()=="VAR_INPUT"}!=set(domains):return None
    machine.max_magnitude=max(abs(integer(v)) for v in domains["rawvalue"])
    if machine.max_magnitude>2**53:return None
    frontier=[(machine,(),expression(machine.get_var("filteredValue")))]
    scans=0
    for t in range(1,depth+1):
        following=[]
        for m,q,previous in frontier:
            for enabled in domains["enable"]:
                step=copy(m);step.mem=deepcopy(m.mem)
                step.set_var("enable",enabled)
                step.mem["rawvalue"]=SampleExpression((t,))
                step.scan()
                scans+=1
                samples=(q+(t,))[-8:] if enabled else ()
                ideal=SampleExpression(samples,0,len(samples)) if enabled else previous
                if (step.get_var("sampleCount")!=len(samples)
                        or step.get_var("windowFull")!=(len(samples)==8)
                        or expression(step.get_var("filteredValue"))!=ideal):
                    return None
                following.append((step,samples,ideal))
        frontier=following
    return dict(depth=depth,symbolic_scans=scans,enable_sequences=len(frontier),
                raw_values_per_scan=len(domains["rawvalue"]),integer_sum_bound=2**53)

"""Bind the existing ST execution model to a private r7 model checker."""
from contextvars import ContextVar
from functools import lru_cache
import r7_revision as v
from conversions import runtime as previous_runtime,UnsupportedConversion,private_module
from stbench.st.interp import SimError


@lru_cache(maxsize=3)
def modelcheck(profile='codesys'):
    previous=previous_runtime(profile)
    mc=private_module('stbench.r7_modelcheck_'+profile,v.ROOT/'modelcheck.py')
    issues=ContextVar('r7_conversion_scope_'+profile,default=None)
    class Interpreter(previous.Interpreter):
        def scan(self):
            try:return super().scan()
            except UnsupportedConversion as exc:
                current=issues.get()
                if current is not None:current.append(str(exc))
                raise SimError('Unsupported modeling: '+str(exc)) from None
    mc.Interpreter=Interpreter
    mc.typecheck=previous.modelcheck.typecheck
    original=mc.check
    def check(*args,**kwargs):
        errors=[];token=issues.set(errors)
        try:report=original(*args,**kwargs)
        finally:issues.reset(token)
        if errors:
            report.error=f'Unsupported modeling: {len(errors)} input transitions use unmodeled conversions; '+errors[0]
            report.r7_unmodeled_conversions=errors
        return report
    mc.check=check
    return mc

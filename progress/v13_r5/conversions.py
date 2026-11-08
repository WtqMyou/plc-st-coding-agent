"""Typed generic integer conversions; original ST tokens and source are unchanged."""
from contextvars import ContextVar
from functools import lru_cache
import importlib.util
from types import SimpleNamespace
import sys
import r5_revision as v
import r3_judge
from stbench.st.frontend import CompileResult,compile_st
from stbench.st.typecheck import Scope
from stbench.st.interp import Interpreter as FrozenInterpreter,SimulationTimeout,SimError

INTEGER_TYPES={
    'SINT':(8,True),'INT':(16,True),'DINT':(32,True),'LINT':(64,True),
    'USINT':(8,False),'UINT':(16,False),'UDINT':(32,False),'ULINT':(64,False),
    'BYTE':(8,False),'WORD':(16,False),'DWORD':(32,False),'LWORD':(64,False)}
SUPPORTED=set(INTEGER_TYPES)|{'BOOL'}
# Recognized CODESYS operators outside the modeled subset remain inconclusive.
KNOWN_TARGETS=SUPPORTED|{'REAL','LREAL','STRING','WSTRING','TIME','LTIME','DATE','LDATE',
    'DT','DATE_AND_TIME','LDT','TOD','TIME_OF_DAY','LTOD','BIT','__UXINT','__XINT','__XWORD'}
GENERIC={'TO_'+name:name for name in KNOWN_TARGETS}


class UnsupportedConversion(RuntimeError):
    """An accepted type/value lies beyond this execution model, not a model-code error."""


class FormulaUnsupportedConversion(SimError):
    """Verification-atom failure: the model checker isolates this single property."""


def bounds(dtype):
    bits,signed=INTEGER_TYPES[dtype]
    return (-(1<<(bits-1)),(1<<(bits-1))-1) if signed else (0,(1<<bits)-1)


def convert(value,source_type,target_type):
    src=(source_type or '').upper();dst=target_type.upper()
    if src not in SUPPORTED or dst not in SUPPORTED:
        raise UnsupportedConversion(f'{src or "unknown"} -> {dst} is not modeled')
    if src=='BOOL':
        if type(value) is not bool:raise UnsupportedConversion('BOOL operand has a non-boolean runtime value')
    else:
        if type(value) is not int:raise UnsupportedConversion('Integer operand has a non-integer runtime value')
        lo,hi=bounds(src)
        if not lo<=value<=hi:raise UnsupportedConversion('Operand exceeds its inferred source range')
    if dst=='BOOL':return bool(value)
    integer=int(value)
    lo,hi=bounds(dst)
    if not lo<=integer<=hi:
        raise UnsupportedConversion(f'Value outside {dst} range [{lo}, {hi}]; narrowing overflow is not modeled')
    return integer


class ConversionChecker(r3_judge.StringChecker):
    def __init__(self,result,profile):
        super().__init__(result,profile)
        self.conversions=[];self.unsupported_conversions=[]

    def infer(self,node,**kwargs):
        name=node.tok.value.upper() if node.tok else ''
        if node.kind!='call' or name not in GENERIC:return super().infer(node,**kwargs)
        dst=GENERIC[name]
        types=[self.infer(arg,writable=False) for arg in node.args]
        node.typ=dst
        if len(node.args)!=1:
            self.err(node.line,'E_ARG_COUNT',f'{name} requires exactly one operand, got {len(node.args)}')
            return dst
        src=(types[0] or '').upper()
        detail=dict(line=node.line,operator=name,source_type=src or None,target_type=dst)
        self.conversions.append(detail)
        if self.scope and self.scope.visible(node.tok.value):
            self.unsupported_conversions.append(dict(detail,reason='conversion operator is shadowed by a declaration'))
        elif src not in SUPPORTED or dst not in SUPPORTED:
            self.unsupported_conversions.append(dict(detail,reason='type pair outside integer/boolean model'))
        return dst


def checked(result,profile='codesys'):
    checker=ConversionChecker(result,profile)
    result.diags.extend(checker.run())
    result.ok=not any(d.level=='error' for d in result.diags)
    return result,checker


class ConversionInterpreter(FrozenInterpreter):
    PROFILE='codesys'

    def _call(self,node):
        name=node.tok.value.upper() if node.tok else ''
        if name not in GENERIC:return super()._call(node)
        try:return self._generic_call(node,name)
        except UnsupportedConversion as exc:
            if self.pou is None:raise FormulaUnsupportedConversion('Unsupported modeling: '+str(exc),node.line) from None
            raise

    def _generic_call(self,node,name):
        if len(node.args)!=1:raise UnsupportedConversion('Invalid conversion arity reached execution')
        operand=node.args[0]
        dtype=operand.typ
        if dtype is None:
            # LTL atoms are parsed separately, without a program type-check pass.
            # Infer against the snapshot's declared types using the same checker.
            result=CompileResult(ok=True,pou=self.pou,structs=self.structs)
            checker=ConversionChecker(result,self.PROFILE)
            checker.scope=Scope(self.pou,self.structs,{n:(t,'VAR') for n,t in self.types.items()})
            dtype=checker.infer(operand,writable=False)
            if checker.diags or checker.unsupported_conversions:
                raise UnsupportedConversion('Cannot establish operand type in verification expression')
        src=(dtype or '').upper();dst=GENERIC[name]
        if src not in SUPPORTED or dst not in SUPPORTED:
            raise UnsupportedConversion(f'{src or "unknown"} -> {dst} is not modeled')
        return convert(self.eval(operand),src,dst)


class _ReturnFromScan(Exception):
    pass


class ControlFlowInterpreter(ConversionInterpreter):
    def scan(self):
        try:super().scan()
        except _ReturnFromScan:pass

    def exec_stmt(self,statement):
        if statement.kind=='return':
            self.steps+=1
            if self.steps>self.MAX_STEPS_PER_CYCLE:raise SimulationTimeout('Scan instruction budget exceeded')
            raise _ReturnFromScan()
        return super().exec_stmt(statement)


def private_module(name,path):
    """Bind dependencies in a fresh module, never mutate any frozen module globals."""
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec)
    sys.modules[name]=module
    spec.loader.exec_module(module)
    return module


@lru_cache(maxsize=6)
def runtime(profile='codesys',return_semantics=True):
    if profile not in ('codesys','openplc','portable'):raise ValueError('Unknown platform profile')
    # The legacy variant is for the explicit conversion-only ablation, never the judge entrypoint.
    suffix=profile+('_returns' if return_semantics else '_legacy_return_diagnostic')
    parent=ControlFlowInterpreter if return_semantics else ConversionInterpreter
    interpreter=type('R5Interpreter_'+suffix,(parent,),{'PROFILE':profile})
    typecheck=lambda result:checked(result,profile)[0]
    driver=private_module('stbench.st.r5_driver_'+suffix,v.ENGINE/'stbench/st/driver.py')
    driver.Interpreter=interpreter;driver.typecheck=typecheck
    driver.check_st=lambda source:typecheck(compile_st(source))
    evaluation=private_module('stbench.r5_evaluation_'+suffix,v.ENGINE/'stbench/evaluation.py')
    evaluation.verify=driver.verify;evaluation.verify_sequence=driver.verify_sequence
    evaluation.typecheck=typecheck
    mc=private_module('stbench.r5_modelcheck_'+suffix,v.PARENT/'modelcheck.py')
    session=ContextVar('r5_conversion_scan_scope_'+suffix,default=None)

    class ModelCheckInterpreter(interpreter):
        def scan(self):
            try:return super().scan()
            except UnsupportedConversion as exc:
                current=session.get()
                if current is not None:current.append(str(exc))
                raise SimError('Unsupported modeling: '+str(exc)) from None

    mc.Interpreter=ModelCheckInterpreter;mc.typecheck=typecheck
    original_check=mc.check

    def check(*args,**kwargs):
        issues=[];token=session.set(issues)
        try:report=original_check(*args,**kwargs)
        finally:session.reset(token)
        if issues:
            report.error=f'Unsupported modeling: {len(issues)} input transitions use unmodeled conversions; '+issues[0]
            report.r5_unmodeled_conversions=issues
        return report

    mc.check=check
    return SimpleNamespace(driver=driver,evaluation=evaluation,modelcheck=mc,Interpreter=interpreter)

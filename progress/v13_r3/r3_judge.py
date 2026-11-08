"""Typed string preflight for the CODESYS benchmark; no frozen module is patched."""
import copy
import json
import re
import subprocess
import sys
import time
from pathlib import Path
import r3_revision as v
import r2_judge as parent
from stbench.st.frontend import compile_st, STD_FUNCS
from stbench.st.typecheck import Checker
from stbench.st.driver import StageResult
from stbench.schema import Problem
from stbench.evaluation import result_from_dict

JUDGE_VERSION='r3-codesys-string-types-v1'
NUMERIC_OPS={'+','-','*','/','MOD','**'}


def is_string(dtype):
    return bool(dtype and re.fullmatch(r'W?STRING(?:\s*\(\s*\d+\s*\))?',dtype.upper()))


class StringChecker(Checker):
    def __init__(self, result, profile):
        super().__init__(result)
        self.profile=profile
        self.string_arithmetic=[]
        self.string_indices=[]

    def infer(self,node,**kwargs):
        result=super().infer(node,**kwargs)
        if node.kind=='call':
            name=node.tok.value.upper() if node.tok else ''
            if name in STD_FUNCS and STD_FUNCS[name][0]=='string':
                node.typ='STRING'
                return node.typ
        if node.kind=='index' and node.args and is_string(node.args[0].typ):
            self.string_indices.append(node.line)
            if len(node.args)==2:
                # Confirmed by the BYTE-index native probe; the frozen interpreter
                # still returns a Python string, so execution is explicitly unsupported.
                node.typ='BYTE'
                return node.typ
        op=node.tok.value.upper() if node.tok else ''
        arithmetic=(node.kind=='binop' and op in NUMERIC_OPS) or (node.kind=='unop' and op in ('+','-'))
        if arithmetic and any(is_string(arg.typ) for arg in node.args):
            issue=dict(line=node.line,operator=op,operand_types=[arg.typ for arg in node.args],
                openplc_concat=(op=='+' and len(node.args)==2 and all(is_string(arg.typ) for arg in node.args)))
            self.string_arithmetic.append(issue)
            if self.profile in ('codesys','portable'):
                self.err(node.line,'E_ARITH_TYPE',f'{op} 的数值操作数不能是 STRING/WSTRING；需要显式数值转换')
        return result


def check_source(source,profile='codesys'):
    if profile not in ('codesys','portable','openplc'):
        raise ValueError('Unknown static profile')
    result=compile_st(source)
    checker=StringChecker(result,profile)
    result.diags.extend(checker.run())
    result.ok=not any(d.level=='error' for d in result.diags)
    return result,checker


def preflight(source,problem,profile):
    p,error=parent.prepare(problem)
    if error is not None:return None,error
    metadata=dict(judge_version=JUDGE_VERSION,static_profile=profile,test_contract_valid=True,
        string_guard_sha256=v.digest(Path(__file__).read_bytes()),candidate_evaluated=True)
    result,checker=check_source(source,profile)
    # OpenPLC's generator accepts some forms rejected by CODESYS. No runtime
    # meaning is inferred from packaging success, nor is native success overwritten.
    unsupported=bool(checker.string_indices or (profile=='openplc' and any(not x['openplc_concat'] for x in checker.string_arithmetic)))
    if unsupported:
        metadata.update(classification='unsupported_modeling',string_indices=checker.string_indices,
            string_arithmetic=checker.string_arithmetic,native_compilation_claimed=False)
        return None,StageResult(compiles=False,tests_total=len(p.test_cases),
            failure_summary='该平台字符串表达式的本地执行模型未实现，不据此判定候选错误',
            mc_error='Unsupported modeling: string arithmetic/index semantics are not modeled for this profile',
            evidence_metadata=metadata)
    if not result.ok:
        errors=[d.to_dict() for d in result.diags if d.level=='error']
        metadata.update(classification='candidate_static_error',native_compilation_claimed=False)
        return None,StageResult(compiles=False,tests_total=len(p.test_cases),compile_errors=errors,
            failure_summary='静态类型检查失败',evidence_metadata=metadata)
    p.provenance['r3_judge']=dict(version=JUDGE_VERSION,profile=profile,guard_sha256=metadata['string_guard_sha256'])
    return p,None


def annotate(result,profile):
    result.evidence_metadata.update(judge_version=JUDGE_VERSION,static_profile=profile,
        string_guard_sha256=v.digest(Path(__file__).read_bytes()),test_contract_valid=True)
    return result


def resolve_native(result,source,problem,backends,*,timeout_s=120,task_remaining_s=None):
    """Resolve only an unsupported local model; never infer behavior from native success."""
    if result.evidence_metadata.get('classification')!='unsupported_modeling':return result
    budget=min(timeout_s,task_remaining_s if task_remaining_s is not None else timeout_s)
    deadline=time.monotonic()+max(0,budget)
    reports={};attempted=False
    for backend in backends:
        original=backend.timeout
        remaining=deadline-time.monotonic()
        if remaining<=0:
            reports[backend.name]=dict(platform=backend.name,status='timeout',diagnostics=['Native boundary deadline reached'])
            continue
        try:
            backend.timeout=min(original,remaining)
            attempted=True
            reports[backend.name]=backend.compile(source,problem).to_dict()
        except (OSError,ValueError,TypeError) as exc:
            reports[backend.name]=dict(platform=backend.name,status='tool_error',diagnostics=[type(exc).__name__+': '+str(exc)])
        finally:backend.timeout=original
    result.platform_results=reports
    result.evidence_metadata['native_compilation_claimed']=attempted
    if any(r['status']=='failed' for r in reports.values()):
        result.evidence_metadata['classification']='candidate_native_error'
        result.failure_summary='所要求的原生编译器拒绝该候选；功能测试未执行'
        result.mc_error=''
        result.compile_errors=[dict(code='E_NATIVE_COMPILE',line=0,platform=name,message='Required native compiler rejected candidate')
            for name,r in reports.items() if r['status']=='failed']
    # passed means compile/package accepted, not a validated simulation model.
    return result


def task_profile(problem):
    platform=problem.provenance.get('platform_adaptation',{}).get('platform')
    return platform if platform in ('codesys','openplc') else 'codesys'


def local_tests(source,problem,*,profile=None):
    if profile is None:profile=task_profile(problem)
    p,error=preflight(source,problem,profile)
    if error is not None:return error
    return annotate(parent.local_tests(source,p),profile)


def evaluate(source,problem,*,profile=None,**kwargs):
    started=time.monotonic()
    platforms={b.name for b in kwargs.get('backends',())}
    if profile is None:
        profile='openplc' if platforms=={'openplc'} else 'portable' if len(platforms)>1 else 'codesys' if 'codesys' in platforms else task_profile(problem)
    if platforms=={'openplc'} and profile!='openplc':
        raise ValueError('An OpenPLC-only native run must use the OpenPLC profile')
    if 'codesys' in platforms and profile=='openplc':
        raise ValueError('A run requiring CODESYS cannot silently use OpenPLC extensions')
    timeout=kwargs.get('timeout_s',parent.base.evaluate.__kwdefaults__['timeout_s'])
    remaining=kwargs.get('task_remaining_s')
    deadline=started+min(timeout,remaining if remaining is not None else timeout)
    budget=deadline-time.monotonic()
    try:
        if budget<=0:raise subprocess.TimeoutExpired('r3 static preflight',max(0,budget))
        proc=subprocess.run([sys.executable,'-B','-X','utf8',str(v.ROOT/'r3_preflight_worker.py')],
            input=json.dumps(dict(code=source,problem=problem.to_dict(),profile=profile)),
            cwd=v.ROOT,capture_output=True,text=True,encoding='utf-8',timeout=budget)
        if proc.returncode:raise RuntimeError(proc.stderr[-1000:])
        payload=json.loads(proc.stdout)
    except (subprocess.TimeoutExpired,RuntimeError,ValueError) as exc:
        return StageResult(compiles=False,tests_total=len(problem.test_cases),
            mc_error='Static preflight timeout' if isinstance(exc,subprocess.TimeoutExpired) else 'Static preflight tool_error',
            evidence_metadata=dict(judge_version=JUDGE_VERSION,classification='tool_error',static_profile=profile))
    budget=max(0,deadline-time.monotonic())
    if 'error' in payload:
        return resolve_native(result_from_dict(payload['error']),source,problem,kwargs.get('backends',()),timeout_s=budget)
    p=Problem.from_dict(payload['problem'])
    next_kwargs=dict(kwargs,timeout_s=budget)
    if remaining is not None:next_kwargs['task_remaining_s']=budget
    if budget<=0:
        return StageResult(compiles=False,tests_total=len(problem.test_cases),mc_error='Static preflight timeout',
            evidence_metadata=dict(judge_version=JUDGE_VERSION,classification='tool_error',static_profile=profile))
    return annotate(parent.evaluate(source,p,**next_kwargs),profile)

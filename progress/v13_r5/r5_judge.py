"""R5 entrypoints use a private typed runtime; no candidate text is rewritten."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import time
import r5_revision as v
from conversions import checked,runtime,UnsupportedConversion
import r3_judge as strings
from stbench.st.frontend import compile_st,tokenize
from stbench.st.driver import StageResult,_collect_domains
from stbench.evaluation import result_from_dict

JUDGE_VERSION='r5-typed-in-range-generic-conversions-v1'


def annotate(result,source,profile):
    result.evidence_metadata.update(judge_version=JUDGE_VERSION,data_version=v.DATA_VERSION,
        static_profile=profile,candidate_source_sha256=v.digest(source.encode()),
        candidate_text_rewritten=False,conversion_scope='representable integer/bit-string/BOOL values only',
        judge_sha256=v.digest(b''.join(p.read_bytes() for p in sorted(v.ROOT.glob('*.py')))),cache_used=False)
    return result


def unsupported(problem,reason,*,details=None):
    return StageResult(compiles=False,tests_total=len(problem.test_cases),
        mc_error='Unsupported modeling: '+reason,failure_summary='本地执行模型范围不足；不判作模型代码错误',
        evidence_metadata=dict(classification='unsupported_modeling',candidate_evaluated=False,
            test_contract_valid=True,unsupported_details=details or []))


def preflight(source,problem,profile):
    p,error=strings.parent.prepare(problem)
    if error is not None:return None,error
    tokens,_=tokenize(source)
    if any(a.value.upper()=='RETURN' and b.value=='(' for a,b in zip(tokens,tokens[1:])):
        return None,unsupported(p,'conditional RETURN syntax is not modeled; bare RETURN is supported')
    result,checker=checked(compile_st(source),profile)
    # Preserve r3's explicitly unmodeled platform string semantics.
    if checker.string_indices or (profile=='openplc' and any(not x['openplc_concat'] for x in checker.string_arithmetic)):
        return None,unsupported(p,'platform string arithmetic/index semantics are not modeled')
    if not result.ok:
        return None,StageResult(compiles=False,tests_total=len(p.test_cases),
            compile_errors=[d.to_dict() for d in result.diags if d.level=='error'],failure_summary='静态类型检查失败',
            evidence_metadata=dict(classification='candidate_static_error',test_contract_valid=True,candidate_evaluated=True))
    if checker.unsupported_conversions:
        return None,unsupported(p,'generic conversion type pair is outside the integer/BOOL subset',details=checker.unsupported_conversions)
    p.provenance['r5_judge']=dict(version=JUDGE_VERSION,profile=profile)
    return p,None


def local_tests(source,problem,*,profile=None):
    profile=profile or strings.task_profile(problem)
    p,error=preflight(source,problem,profile)
    if error is not None:return annotate(error,source,profile)
    groups={}
    for case in p.test_cases:
        mode=case.mode or p.case_mode
        if mode!='single' and not mode.startswith('sequence'):raise ValueError('Unsupported test group: '+mode)
        groups.setdefault(mode,[]).append(case)
    results=[];engine=runtime(profile)
    try:
        for mode,cases in groups.items():
            one=copy.deepcopy(p);one.case_mode='single' if mode=='single' else 'sequence'
            one.test_cases=copy.deepcopy(cases)
            for case in one.test_cases:case.mode=one.case_mode
            r=engine.evaluation.local_tests(source,one)
            for case in r.cases:case.mode=mode
            results.append(r)
    except UnsupportedConversion as exc:
        return annotate(unsupported(problem,str(exc)),source,profile)
    if not results:
        return annotate(StageResult(compiles=True,tests_total=0,failure_summary='No functional test cases'),source,profile)
    out=copy.deepcopy(results[0]);out.compiles=all(r.compiles for r in results)
    out.tests_total=sum(r.tests_total for r in results);out.tests_passed=sum(r.tests_passed for r in results)
    out.cases=[c for r in results for c in r.cases];out.compile_errors=[e for r in results for e in r.compile_errors]
    out.failure_summary=next((r.failure_summary for r in results if r.failure_summary),'')
    out.evidence_metadata.update(classification='evaluated',test_contract_valid=True,candidate_evaluated=True,
        group_counts={mode:len(cases) for mode,cases in groups.items()},
        group_policy='fresh instance per sequence group; each single case fresh')
    return annotate(out,source,profile)


def attach_model_check(source,problem,out,profile):
    out.mc_executed=True
    specs=[(s.sid,s.ltl) for s in problem.specs if s.ltl.strip()];out.mc_specs_total=len(specs)
    if not specs:out.mc_error='No executable LTL properties';return out
    if any(x.data_type.upper()=='VARIANT' for x in problem.variables):
        out.mc_error='Unsupported modeling: generic VARIANT binding is not quantified'
        out.mc_specs_inconclusive=len(specs);return out
    mc=runtime(profile).modelcheck
    try:
        rep=mc.check(source,specs,mc.InputSpace(_collect_domains(problem),tuple(problem.mc_fixed_inputs)),
            max_depth=problem.mc_max_depth,max_traces=problem.mc_max_traces,max_seconds=problem.mc_max_seconds,
            program_name=problem.pid,observer_name=problem.provenance.get('r9_spec_policy',{}).get('observer'),
            observable_names={x.name for x in problem.variables})
    except UnsupportedConversion as exc:
        out.mc_error='Unsupported modeling: '+str(exc);out.mc_specs_inconclusive=len(specs)
        return out
    out.mc_states=rep.states_explored;out.mc_traces=rep.traces_explored;out.mc_truncated=rep.truncated
    out.mc_fixed_input_domains=rep.fixed_input_domains;out.mc_error=rep.error
    for s in rep.specs:
        if s.contradicting:
            out.mc_specs_violated+=1
            out.mc_violations.append(dict(id=s.spec_id,formula=s.formula,at=s.ce_at,explanation=s.explanation,trace=s.counterexample))
        elif s.inconclusive or rep.error:out.mc_specs_inconclusive+=1
        elif s.holds:out.mc_specs_hold+=1
    if rep.error:out.mc_specs_inconclusive+=max(0,len(specs)-len(rep.specs))
    out.evidence_metadata['r5_model_check']=rep.to_dict()
    if hasattr(rep,'r5_unmodeled_conversions'):
        out.evidence_metadata['r5_model_check']['unmodeled_conversions']=rep.r5_unmodeled_conversions
    return out


def evaluate(source,problem,*,profile=None,model_check=True,timeout_s=60.,task_remaining_s=None,
             backends=(),verification_after_tests=False,cache_dir=None):
    platforms={b.name for b in backends}
    if profile is None:
        profile='openplc' if platforms=={'openplc'} else 'portable' if len(platforms)>1 else 'codesys' if 'codesys' in platforms else strings.task_profile(problem)
    if (platforms=={'openplc'} and profile!='openplc') or ('codesys' in platforms and profile=='openplc'):
        raise ValueError('Static and required native profiles conflict')
    deadline=time.monotonic()+max(0,min(timeout_s,task_remaining_s if task_remaining_s is not None else timeout_s))

    def worker(mode,result=None):
        budget=deadline-time.monotonic()
        if budget<=0:raise subprocess.TimeoutExpired('r5 worker',0)
        p=copy.deepcopy(problem);p.mc_max_seconds=min(p.mc_max_seconds,budget)
        prior=result.to_dict() if result else None
        if prior:prior.update({'mc_'+key:value for key,value in prior.pop('model_check',{}).items()})
        proc=subprocess.run([sys.executable,'-B','-X','utf8',str(v.ROOT/'r5_worker.py')],
            input=json.dumps(dict(mode=mode,code=source,problem=p.to_dict(),profile=profile,result=prior)),
            cwd=v.REPO,capture_output=True,text=True,encoding='utf-8',timeout=budget)
        if proc.returncode:raise RuntimeError(proc.stderr[-1200:])
        return result_from_dict(json.loads(proc.stdout))

    out=None
    try:
        out=worker('local')
        if out.evidence_metadata.get('classification')=='unsupported_modeling':
            out=strings.resolve_native(out,source,problem,backends,timeout_s=max(0,deadline-time.monotonic()))
            return annotate(out,source,profile)
        if not out.compiles:return out
        for backend in backends:
            remaining=deadline-time.monotonic()
            if remaining<=0:raise subprocess.TimeoutExpired('r5 native deadline',0)
            original=backend.timeout
            try:
                backend.timeout=min(original,remaining);out.platform_results[backend.name]=backend.compile(source,problem).to_dict()
            finally:backend.timeout=original
        if any(r['status']!='passed' for r in out.platform_results.values()):return out
        if model_check and (not verification_after_tests or out.all_tests_passed):out=worker('mc',out)
    except (subprocess.TimeoutExpired,RuntimeError,ValueError,OSError) as exc:
        if out is None:out=StageResult(compiles=False,tests_total=len(problem.test_cases))
        out.mc_error='r5 worker timeout' if isinstance(exc,subprocess.TimeoutExpired) else 'r5 tool_error: '+str(exc)
        out.evidence_metadata['classification']='tool_error'
    return annotate(out,source,profile)

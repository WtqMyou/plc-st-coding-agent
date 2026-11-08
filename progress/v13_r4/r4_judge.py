"""Offline r4 judge: group isolation and bounded per-property verification."""
import copy
import json
import subprocess
import sys
import time
import r4_revision as v
import r3_judge as parent
from stbench.st.driver import StageResult, _collect_domains
from stbench.evaluation import result_from_dict

JUDGE_VERSION='r4-isolated-groups-and-properties-v1'


def local_tests(source, problem, *, profile=None):
    problem,error=parent.parent.prepare(problem)
    if error is not None:return error
    groups={}
    for case in problem.test_cases:
        mode=case.mode or problem.case_mode
        if mode!='single' and not mode.startswith('sequence'):
            raise ValueError('Unsupported test group: '+mode)
        groups.setdefault(mode,[]).append(case)
    results=[]
    for mode,cases in groups.items():
        p=copy.deepcopy(problem)
        p.case_mode='single' if mode=='single' else 'sequence'
        p.test_cases=copy.deepcopy(cases)
        for case in p.test_cases:case.mode=p.case_mode
        r=parent.local_tests(source,p,profile=profile)
        for case in r.cases:case.mode=mode
        results.append(r)
    if not results:return parent.local_tests(source,problem,profile=profile)
    out=copy.deepcopy(results[0])
    out.compiles=all(r.compiles for r in results)
    out.tests_total=sum(r.tests_total for r in results)
    out.tests_passed=sum(r.tests_passed for r in results)
    out.cases=[c for r in results for c in r.cases]
    out.compile_errors=[e for r in results for e in r.compile_errors]
    out.failure_summary=next((r.failure_summary for r in results if r.failure_summary),'')
    out.evidence_metadata.update(judge_version=JUDGE_VERSION,data_version=v.VERSION,
        group_counts={mode:len(cases) for mode,cases in groups.items()},
        group_policy='fresh function-block instance per sequence group; single cases each fresh')
    return out


def attach_model_check(source,problem,out):
    mc=v.load_modelcheck()
    out.mc_executed=True
    specs=[(s.sid,s.ltl) for s in problem.specs if s.ltl.strip()]
    out.mc_specs_total=len(specs)
    if not specs:
        out.mc_error='No executable LTL properties';return out
    if any(x.data_type.upper()=='VARIANT' for x in problem.variables):
        out.mc_specs_inconclusive=len(specs)
        out.mc_error='Unsupported modeling: generic VARIANT binding is not quantified';return out
    domains=_collect_domains(problem)
    rep=mc.check(source,specs,mc.InputSpace(domains,tuple(problem.mc_fixed_inputs)),
        max_depth=problem.mc_max_depth,max_traces=problem.mc_max_traces,max_seconds=problem.mc_max_seconds,
        program_name=problem.pid,observer_name=problem.provenance.get('r9_spec_policy',{}).get('observer'),
        observable_names={x.name for x in problem.variables})
    out.mc_states=rep.states_explored;out.mc_traces=rep.traces_explored
    out.mc_truncated=rep.truncated;out.mc_fixed_input_domains=rep.fixed_input_domains
    out.mc_error=rep.error
    # A global simulation error invalidates holds, but cannot erase known violations.
    for s in rep.specs:
        if s.contradicting:
            out.mc_specs_violated+=1
            out.mc_violations.append(dict(id=s.spec_id,formula=s.formula,at=s.ce_at,
                explanation=s.explanation,trace=s.counterexample))
        elif s.inconclusive or rep.error:out.mc_specs_inconclusive+=1
        elif s.holds:out.mc_specs_hold+=1
    if rep.error:out.mc_specs_inconclusive+=max(0,len(specs)-len(rep.specs))
    out.evidence_metadata['r4_model_check']=rep.to_dict()
    return out


def evaluate(source,problem,*,profile=None,model_check=True,timeout_s=60.,task_remaining_s=None,
             backends=(),verification_after_tests=False,cache_dir=None):
    """No model access. One total deadline covers workers and native compilation."""
    platforms={b.name for b in backends}
    if profile is None:
        profile='openplc' if platforms=={'openplc'} else 'portable' if len(platforms)>1 else 'codesys' if 'codesys' in platforms else parent.task_profile(problem)
    if (platforms=={'openplc'} and profile!='openplc') or ('codesys' in platforms and profile=='openplc'):
        raise ValueError('Static and required native profiles conflict')
    deadline=time.monotonic()+max(0,min(timeout_s,task_remaining_s if task_remaining_s is not None else timeout_s))

    def worker(mode,result=None):
        budget=deadline-time.monotonic()
        if budget<=0:raise subprocess.TimeoutExpired('r4 worker',0)
        p=copy.deepcopy(problem)
        p.mc_max_seconds=min(p.mc_max_seconds,budget)
        prior=result.to_dict() if result else None
        if prior:
            prior.update({'mc_'+k:value for k,value in prior.pop('model_check',{}).items()})
        proc=subprocess.run([sys.executable,'-B','-X','utf8',str(v.ROOT/'r4_worker.py')],
            input=json.dumps(dict(mode=mode,code=source,problem=p.to_dict(),profile=profile,
                result=prior)),cwd=v.REPO,
            capture_output=True,text=True,encoding='utf-8',timeout=budget)
        if proc.returncode:raise RuntimeError(proc.stderr[-1200:])
        return result_from_dict(json.loads(proc.stdout))

    out=None
    try:
        out=worker('local')
        if out.evidence_metadata.get('classification')=='unsupported_modeling':
            return parent.resolve_native(out,source,problem,backends,timeout_s=max(0,deadline-time.monotonic()))
        if not out.compiles:return out
        for backend in backends:
            remaining=deadline-time.monotonic()
            if remaining<=0:raise subprocess.TimeoutExpired('r4 native deadline',0)
            original=backend.timeout
            try:
                backend.timeout=min(original,remaining)
                out.platform_results[backend.name]=backend.compile(source,problem).to_dict()
            finally:backend.timeout=original
        if any(r['status']!='passed' for r in out.platform_results.values()):return out
        if model_check and (not verification_after_tests or out.all_tests_passed):out=worker('mc',out)
    except (subprocess.TimeoutExpired,RuntimeError,ValueError,OSError) as exc:
        if out is None:out=StageResult(compiles=False,tests_total=len(problem.test_cases))
        out.mc_error='r4 worker timeout' if isinstance(exc,subprocess.TimeoutExpired) else 'r4 tool_error: '+str(exc)
        out.evidence_metadata['classification']='tool_error'
    out.evidence_metadata.update(judge_version=JUDGE_VERSION,data_version=v.VERSION,
        judge_sha256=v.digest(b''.join((v.ROOT/name).read_bytes() for name in
            ('r4_judge.py','r4_worker.py','modelcheck.py','ORIGIN_R3.json'))),cache_used=False)
    return out

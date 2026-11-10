"""R5 functional/native evaluation plus an independently bounded r7 formula worker."""
import copy
import json
import subprocess
import sys
import time
import r7_revision as v
import r5_judge as previous
from r7_runtime import modelcheck
from stbench.st.driver import _collect_domains
from stbench.evaluation import result_from_dict


def annotate(result):
    result.evidence_metadata.update(judge_version=v.VERSION,data_version=v.DATA_VERSION,
        functional_data_version=v.r6.VERSION,execution_model='v1.3-judge-r5',candidate_text_rewritten=False,
        formula_judge_sha256=v.digest(b''.join(p.read_bytes() for p in sorted(v.ROOT.glob('*.py')))))
    return result


def local_tests(source,problem,*,profile=None):
    return annotate(previous.local_tests(source,problem,profile=profile))


def attach_model_check(source,problem,result,profile):
    specs=[(s.sid,s.ltl) for s in problem.specs if s.ltl.strip()]
    result.mc_executed=True;result.mc_specs_total=len(specs)
    if not specs:result.mc_error='No executable LTL properties';return annotate(result)
    if any(x.data_type.upper()=='VARIANT' for x in problem.variables):
        result.mc_error='Unsupported modeling: generic VARIANT binding is not quantified'
        result.mc_specs_inconclusive=len(specs);return annotate(result)
    mc=modelcheck(profile)
    report=mc.check(source,specs,mc.InputSpace(_collect_domains(problem),tuple(problem.mc_fixed_inputs)),
        max_depth=problem.mc_max_depth,max_traces=problem.mc_max_traces,max_seconds=problem.mc_max_seconds,
        program_name=problem.pid,observer_name=problem.provenance.get('r9_spec_policy',{}).get('observer'),
        observable_names={x.name for x in problem.variables})
    result.mc_states=report.states_explored;result.mc_traces=report.traces_explored
    result.mc_truncated=report.truncated;result.mc_fixed_input_domains=report.fixed_input_domains;result.mc_error=report.error
    for spec in report.specs:
        if spec.contradicting:
            result.mc_specs_violated+=1
            result.mc_violations.append(dict(id=spec.spec_id,formula=spec.formula,at=spec.ce_at,
                explanation=spec.explanation,trace=spec.counterexample))
        elif spec.inconclusive or report.error:result.mc_specs_inconclusive+=1
        elif spec.holds:result.mc_specs_hold+=1
    if report.error:result.mc_specs_inconclusive+=max(0,len(specs)-len(report.specs))
    result.evidence_metadata['r7_model_check']=report.to_dict()
    if hasattr(report,'r7_unmodeled_conversions'):
        result.evidence_metadata['r7_model_check']['unmodeled_conversions']=report.r7_unmodeled_conversions
    return annotate(result)


def evaluate(source,problem,*,profile=None,model_check=True,timeout_s=60.,task_remaining_s=None,
             backends=(),verification_after_tests=False,cache_dir=None):
    deadline=time.monotonic()+max(0,min(timeout_s,task_remaining_s if task_remaining_s is not None else timeout_s))
    platforms={backend.name for backend in backends}
    if profile is None:
        profile='openplc' if platforms=={'openplc'} else 'portable' if len(platforms)>1 else 'codesys' if 'codesys' in platforms else previous.strings.task_profile(problem)
    result=previous.evaluate(source,problem,profile=profile,model_check=False,timeout_s=timeout_s,
        task_remaining_s=task_remaining_s,backends=backends,cache_dir=cache_dir)
    allowed=result.compiles and result.evidence_metadata.get('classification')=='evaluated'
    allowed=allowed and all(row['status']=='passed' for row in result.platform_results.values())
    if not model_check or not allowed or (verification_after_tests and not result.all_tests_passed):return annotate(result)
    remaining=deadline-time.monotonic()
    if remaining<=0:
        result.mc_error='r7 total deadline reached';result.evidence_metadata['classification']='tool_error'
        return annotate(result)
    p=copy.deepcopy(problem);p.mc_max_seconds=min(p.mc_max_seconds,remaining)
    prior=result.to_dict();prior.update({'mc_'+key:value for key,value in prior.pop('model_check',{}).items()})
    try:
        proc=subprocess.run([sys.executable,'-B','-X','utf8',str(v.ROOT/'r7_worker.py')],
            input=json.dumps(dict(source=source,problem=p.to_dict(),profile=profile,result=prior)),
            cwd=v.REPO,capture_output=True,text=True,encoding='utf-8',timeout=remaining)
        if proc.returncode:raise RuntimeError(proc.stderr[-1200:])
        result=result_from_dict(json.loads(proc.stdout))
    except (subprocess.TimeoutExpired,RuntimeError,ValueError,OSError) as exc:
        result.mc_error='r7 worker timeout' if isinstance(exc,subprocess.TimeoutExpired) else 'r7 tool_error: '+str(exc)
        result.evidence_metadata['classification']='tool_error'
    return annotate(result)

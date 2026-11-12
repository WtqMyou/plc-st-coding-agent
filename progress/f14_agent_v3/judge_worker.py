"""Live-study judge stages isolated from the old r7 package namespace."""
import hashlib
import json
from pathlib import Path
import sys
RELEASE=Path(__file__).resolve().parent/'release'
sys.path.insert(0,str(RELEASE))
from stbench.schema import Problem
from stbench.evaluation import local_tests,evaluate,check_interface,feedback_for_agent,verification_status
from stbench.st.driver import StageResult,_compile_errors
from stbench.st.frontend import compile_st, ELEMENTARY

def safe_feedback(result,problem):
    text=feedback_for_agent(result)
    failed=next((c for c in result.cases if not c.passed),None)
    if failed is None:return text
    target=next((c for c in problem.test_cases if c.tc_id==failed.tc_id),None)
    if target is None:return text
    public={v.name.lower() for v in problem.variables}
    sequence=[]
    for case in problem.test_cases:
        if (case.mode or problem.case_mode)==(target.mode or problem.case_mode) and case.group==target.group:
            sequence.append(dict(case=case.tc_id,inputs=case.inputs,const_inputs=case.const_inputs,
                initial_interface_values={k:v for k,v in case.init.items() if k.lower() in public},cycles=case.cycles,scan_interval_ms=case.scan_interval_ms))
        if case is target:break
    if (target.mode or problem.case_mode)=='single':sequence=sequence[-1:]
    omitted=False
    while len(sequence)>1 and len(json.dumps(sequence,ensure_ascii=False))>2000:
        sequence.pop(0);omitted=True
    actual=failed.to_dict()['actual']
    payload=dict(failed_case=failed.tc_id,mode=failed.mode,prefix_omitted=omitted,input_trace=sequence,observed_outputs=actual)
    if len(json.dumps(payload,ensure_ascii=False))>2700:
        payload=dict(failed_case=failed.tc_id,mode=failed.mode,input_trace_omitted_for_size=True,observed_outputs=actual)
    return text+'\nObserved execution (no expected values or test notes):\n'+json.dumps(payload,ensure_ascii=False)

def main():
    request=json.load(sys.stdin);pid=request['pid'];mode=request['mode'];code=request['source']
    paths=list(RELEASE.glob('datasets/*/'+pid+'.json'))
    if len(paths)!=1 or Path(pid).name!=pid:raise ValueError('Unknown exact task ID')
    problem=Problem.load(paths[0])
    if mode=='static':
        ok,errors,summary=_compile_errors(code)
        if ok:errors=check_interface(code,problem);ok=not errors
        result=StageResult(compiles=ok,compile_errors=errors,tests_total=len(problem.test_cases),failure_summary=summary if not ok else '')
    elif mode=='functional':
        parsed=compile_st(code);declared={k.upper() for k in parsed.structs};unknown=[]
        if parsed.pou:
            for d in parsed.pou.decls:
                dtype=d.data_type.upper()
                if " OF " in dtype:dtype=dtype.rsplit(" OF ",1)[1].strip()
                if dtype not in ELEMENTARY and dtype not in declared and dtype not in ("TON","R_TRIG","F_TRIG","VARIANT","ANY") and not dtype.startswith(("STRING","WSTRING")):
                    unknown.append(dtype)
        if unknown:
            result=StageResult(compiles=True,tests_total=len(problem.test_cases),mc_error="Unsupported modeling: library types "+", ".join(sorted(set(unknown))))
        else:result=local_tests(code,problem)
    elif mode=='bounded':
        seconds=min(30,max(.1,float(request['seconds'])))
        problem.mc_max_seconds=min(problem.mc_max_seconds,seconds)
        result=evaluate(code,problem,model_check=True,verification_after_tests=True,timeout_s=seconds+5,task_remaining_s=seconds+5)
    else:raise ValueError('Unknown judge stage')
    result.evidence_metadata.update(data_version='STBench-F1.4',distribution='STBench-F1.4-P1',stage=mode,
        candidate_text_rewritten=False,source_sha256=hashlib.sha256(code.encode()).hexdigest(),
        task_json_sha256=hashlib.sha256(paths[0].read_bytes()).hexdigest(),functional_execution='Python scan interpreter',
        classification='unsupported_modeling' if result.mc_error.startswith('Unsupported modeling:') else 'tool_error' if result.mc_error else 'evaluated')
    parsed=compile_st(code)
    print(json.dumps(dict(result=result.to_dict(),complete_code=bool(parsed.ok and parsed.pou is not None),
        verification_status='inconclusive' if result.mc_error.startswith('Unsupported modeling:') else verification_status(result),feedback=safe_feedback(result,problem)),ensure_ascii=False))

if __name__=='__main__':main()

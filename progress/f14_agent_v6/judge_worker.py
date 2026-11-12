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

def safe_feedback(result,problem,contract_report=None):
    from v6_contracts import relevant_clauses
    from stbench.st.driver import _match
    users=json.loads((RELEASE/'agent_inputs.json').read_text(encoding='utf-8'))
    status=verification_status(result)
    lines=[f"Functional checks: {result.tests_passed}/{result.tests_total}; bounded status: {status}."]
    if not result.compiles:
        lines += [f"Line {d.get('line',0)} [{d.get('code','E')}]: {d.get('message','')}" for d in result.compile_errors[:6]]
    public={v.name.lower() for v in problem.variables};targets={c.tc_id:c for c in problem.test_cases}
    groups={}
    for case in result.cases:
        if case.passed:continue
        target=targets.get(case.tc_id)
        if target is None:continue
        names=tuple(sorted(k for k in case.expected if k.lower() in public and not _match(case.actual.get(k),case.expected[k])))
        if not names:names=tuple(sorted(case.actual))
        key=(target.group,target.mode or problem.case_mode)
        groups.setdefault(key,[])
        if len(groups[key])<3:groups[key].append((case,target,names))
    examples=[]
    for (group,mode),selected in list(groups.items())[:3]:
        last=selected[-1][1];trace=[]
        for case in problem.test_cases:
            if case.group==group and (case.mode or problem.case_mode)==mode:
                trace.append(dict(case=case.tc_id,inputs=case.inputs,const_inputs=case.const_inputs,
                    initial_interface_values={k:v for k,v in case.init.items() if k.lower() in public},
                    private_initial_state_present=any(k.lower() not in public for k in case.init),
                    initial_state_scope='public_interface_only',cycles=case.cycles,scan_interval_ms=case.scan_interval_ms))
            if case is last:break
        if mode=='single':
            # Independent cases are never concatenated as if they shared state.
            trace=[step for step in trace if step['case']==last.tc_id];selected=[selected[-1]]
        names=sorted({n for _,_,fields in selected for n in fields})
        example=dict(mode=mode,prefix_omitted=False,input_trace=trace,
            checkpoints=[dict(case=failed.tc_id,check_outputs=list(fields),observed_outputs=failed.to_dict()['actual']) for failed,_,fields in selected],
            relevant_public_clauses=relevant_clauses(users[problem.pid]['user'],problem.variables,names,2))
        examples.append(example)
    for violation in result.mc_violations[:3]:
        lines.append(f"Confirmed bounded property violation: {violation['id']}, position {violation.get('at')}. Review the public contract; no private observer definitions are provided.")
    if contract_report and contract_report.get('violations'):
        lines.append('Candidate-declared contract check: '+json.dumps(contract_report,ensure_ascii=False))
    text='\n'.join(lines)
    while examples:
        payload='\nComplete public input prefixes and observed executions (initial-state scope is explicit; no assertion values or test notes):\n'+json.dumps(examples,ensure_ascii=False)
        if len((text+payload).encode())<=24000:return text+payload
        examples.pop()
    return text+'\nReplay group omitted for size; no incomplete prefix is presented as a complete trace.' if groups else text

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
        else:
            result=local_tests(code,problem)
            unsupported=next((c.message for c in result.cases if 'Unsupported modeling:' in c.message),'')
            if unsupported:result.mc_error='Unsupported modeling: '+unsupported
    elif mode=='bounded':
        seconds=min(30,max(.1,float(request['seconds'])))
        problem.mc_max_seconds=min(problem.mc_max_seconds,seconds)
        result=evaluate(code,problem,model_check=True,verification_after_tests=True,timeout_s=seconds+5,task_remaining_s=seconds+5)
    else:raise ValueError('Unknown judge stage')
    contract_report={}
    if mode=='functional' and result.compiles and not result.mc_error:
        from contract_check import check
        contract_report=check(code,problem)
        result.evidence_metadata['declared_contract_check']=contract_report
    result.evidence_metadata.update(data_version='STBench-F1.4',distribution='STBench-F1.4-P1',stage=mode,
        candidate_text_rewritten=False,source_sha256=hashlib.sha256(code.encode()).hexdigest(),
        task_json_sha256=hashlib.sha256(paths[0].read_bytes()).hexdigest(),functional_execution='Python scan interpreter',
        string_index_mode='codesys_zero_based_byte',compound_assignment='value_copy',classification='unsupported_modeling' if result.mc_error.startswith('Unsupported modeling:') else 'tool_error' if result.mc_error else 'evaluated')
    parsed=compile_st(code)
    print(json.dumps(dict(result=result.to_dict(),complete_code=bool(parsed.ok and parsed.pou is not None),
        verification_status='inconclusive' if result.mc_error.startswith('Unsupported modeling:') else verification_status(result),feedback=safe_feedback(result,problem,contract_report)),ensure_ascii=False))

if __name__=='__main__':main()

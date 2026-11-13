"""Candidate-only timer observations; no expected outputs or reference state."""
from stbench.st.frontend import compile_st
from stbench.st.typecheck import typecheck
from stbench.st.interp import Interpreter, StructValue

def observe(source,problem,steps,mode):
    parsed=typecheck(compile_st(source))
    if not parsed.ok or parsed.pou is None:return []
    if not any(d.data_type.upper()=='TON' for d in parsed.pou.decls):return []
    targets={c.tc_id:c for c in problem.test_cases};public={v.name.lower() for v in problem.variables}
    if any(s.get('private_initial_state_present') for s in steps):return []
    engine=None;rows=[]
    for step in steps:
        tc=targets[step['case']]
        if engine is None or mode=='single':engine=Interpreter(parsed.pou,parsed.structs)
        for name,value in tc.init.items():
            if name.lower() not in public:return []
            engine.set_var(name,value)
        values={k.lower():v for k,v in tc.inputs.items()};const={k.lower():v for k,v in tc.const_inputs.items()}
        for name,value in const.items():engine.set_var(name,value)
        for var in problem.inputs:
            low=var.name.lower()
            if low in values:engine.set_var(var.name,values[low])
            elif low not in const and engine.types.get(low,'').upper()=='BOOL':engine.set_var(var.name,False)
        for _ in range(max(1,int(tc.cycles or 1))):engine.scan(tc.scan_interval_ms)
        timers={}
        for name,value in engine.mem.items():
            if isinstance(value,StructValue) and value.type_name=='TON':
                timers[name]={k:v for k,v in value.values.items() if k in ('IN','PT','Q','ET')}
        rows.append(dict(case=tc.tc_id,candidate_clock_ms=engine.clock_ms,candidate_timers=timers))
    return rows

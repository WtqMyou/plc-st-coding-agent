"""Check candidate-declared public Boolean latch rules on independently generated traces."""
import json
import re


def declared_rules(source):
    match=re.search(r'\(\*\s*CONTRACT_RULES\s*(.*?)\*\)',source,re.I|re.S)
    if not match:return [],'not_declared'
    try:
        rules=json.loads(match.group(1))
        if not isinstance(rules,list) or len(rules)>12:raise ValueError('Rule list exceeds the supported schema')
        return rules,'declared'
    except (ValueError,TypeError):return [],'invalid_json'


def check(source,problem):
    from stbench.st.typecheck import check_st
    from stbench.st.interp import Interpreter,SimError,SimulationTimeout,_plain_value
    rules,status=declared_rules(source)
    report=dict(status=status,supported=0,unsupported=0,violations=[],generated_from='candidate declarations and public Boolean interface only')
    parsed=check_st(source)
    if not parsed.ok:return dict(report,status='local_syntax_unresolved')
    inputs={v.name.lower():v.name for v in problem.inputs if v.data_type.upper()=='BOOL'}
    outputs={v.name.lower():v.name for v in problem.outputs if v.data_type.upper()=='BOOL'}
    for rule in rules:
        if not isinstance(rule,dict):report['unsupported']+=1;continue
        output=outputs.get(str(rule.get('output','')).lower())
        activate=inputs.get(str(rule.get('set_input','')).lower())
        reset=inputs.get(str(rule.get('reset_input','')).lower()) if rule.get('reset_input') else None
        if rule.get('kind')!='hold_until_reset' or not output or not activate or (rule.get('reset_input') and not reset) or reset==activate:
            report['unsupported']+=1;continue
        report['supported']+=1
        others=[name for name in inputs.values() if name not in (activate,reset)]
        for disturbance in [None,*others]:
            engine=Interpreter(parsed.pou,parsed.structs)
            zero={name:False for name in inputs.values()}
            scans=[dict(zero,**{activate:True}),dict(zero)]
            if disturbance:scans[-1][disturbance]=True
            if reset:scans.append(dict(zero,**{reset:True}))
            trace=[]
            try:
                for index,values in enumerate(scans):
                    for name,value in values.items():engine.set_var(name,value)
                    engine.scan(20)
                    observed={name:_plain_value(engine.get_var(name)) for name in outputs.values()}
                    trace.append(dict(inputs=values,scan_interval_ms=20,observed_outputs=observed))
                    wanted=index<2
                    if bool(observed[output])!=wanted:
                        report['violations'].append(dict(rule=rule,step=index,
                            kind='activation' if index==0 else 'retention' if index==1 else 'reset',trace=trace,
                            interpretation='Candidate-declared rule disagrees with its implementation; review against the public task'))
                        break
            except (SimError,SimulationTimeout,ValueError,TypeError) as exc:
                report.setdefault('unresolved',[]).append(type(exc).__name__)
            if len(report['violations'])>=4:return report
    return report

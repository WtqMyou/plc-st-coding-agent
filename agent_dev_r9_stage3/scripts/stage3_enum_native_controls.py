"""Real CODESYS enum controls. No model, ledger or prior-evidence mutations."""
from stbench.campaign import digest
from stbench.platforms import CodesysBackend
from stbench.schema import Problem
from stbench.evaluation import atomic_json

BASE = ('TYPE GateState:(Idle,Active); END_TYPE FUNCTION_BLOCK FB '
        'VAR_OUTPUT ok:BOOL; END_VAR VAR enumValue:GateState; integerValue:INT; END_VAR '
        '{body} ok:=TRUE; END_FUNCTION_BLOCK')


def check_enum_controls(cfg, out):
    p=Problem.from_dict(dict(pid='stage3-enum-control',source='selfmade',difficulty='easy',
        title='enum compiler control',requirements='enum compilation',
        variables=[dict(name='ok',data_type='BOOL',direction='output')]))
    strict="{attribute 'strict'} {attribute 'qualified_only'} "+BASE
    cases=[('plain_positive',BASE.replace('{body}','enumValue:=integerValue; enumValue:=enumValue+1;'),'passed'),
           ('strict_positive',strict.replace('{body}','enumValue:=GateState.Active;'),'passed'),
           ('strict_arithmetic_negative',strict.replace('{body}','enumValue:=enumValue+1;'),'failed'),
           ('constant_write_negative',BASE.replace('{body}','Idle:=1;'),'failed')]
    backend=CodesysBackend(cfg);rows=[]
    for name,source,expected in cases:
        result=backend.compile(source,p)
        rows.append(dict(name=name,expected=expected,result=result.to_dict()))
    passed=all(r['result']['status']==r['expected'] for r in rows)
    proof=dict(passed=passed,source_sha256=digest(),platform_identity=backend.identity(),rows=rows,model_requests=0)
    atomic_json(out/'enum_native_controls.json',proof)
    if not passed:
        raise RuntimeError('Enum native controls failed; no model request sent')
    return proof

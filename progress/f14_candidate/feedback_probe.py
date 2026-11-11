"""Synthetic offline feedback fixture, excluded from the 35-task benchmark."""
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent/'release'))
from stbench.schema import Problem
from stbench.evaluation import evaluate,feedback_for_agent,verification_status

problem=Problem.from_dict(dict(pid='offline-feedback-probe',source='selfmade',difficulty='easy',title='Offline probe',
    requirements='Copy request into actual every scan.',case_mode='single',
    variables=[dict(name='request',data_type='BOOL',direction='input',description=''),dict(name='actual',data_type='BOOL',direction='output',description='')],
    specs=[dict(sid='probe-S1',text='Output follows the request.',ltl='G(actual = request)',kind='safety')],
    test_cases=[dict(tc_id='probe-zero',inputs=dict(request=False),expected=dict(actual=False))],
    mc_inputs=dict(request=[False,True]),mc_max_depth=2,mc_max_traces=20,mc_max_seconds=2))
bad='FUNCTION_BLOCK FB VAR_INPUT request:BOOL; END_VAR VAR_OUTPUT actual:BOOL; END_VAR actual:=FALSE; END_FUNCTION_BLOCK'
good=bad.replace('actual:=FALSE;','actual:=request;')
wrong=evaluate(bad,problem,model_check=True,verification_after_tests=True,timeout_s=5)
right=evaluate(good,problem,model_check=True,verification_after_tests=True,timeout_s=5)
assert wrong.compiles and wrong.all_tests_passed and verification_status(wrong)=='violated'
assert right.compiles and right.all_tests_passed and verification_status(right)=='bounded_pass'
print(json.dumps(dict(synthetic=True,counted_in_35_tasks=False,bad_source=bad,good_source=good,
    user='Write FUNCTION_BLOCK FB with BOOL input request and BOOL output actual. Copy request to actual every scan.',
    feedback=feedback_for_agent(wrong),before=wrong.to_dict(),after=right.to_dict()),ensure_ascii=False))

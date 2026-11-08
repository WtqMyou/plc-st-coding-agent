"""Private bounded worker, never launches a model or reads API credentials."""
import json
import sys
import r4_judge as judge
from stbench.schema import Problem
from stbench.evaluation import result_from_dict

if __name__=='__main__':
    payload=json.load(sys.stdin)
    p=Problem.from_dict(payload['problem'])
    if payload['mode']=='local':
        r=judge.local_tests(payload['code'],p,profile=payload['profile'])
    elif payload['mode']=='mc':
        r=judge.attach_model_check(payload['code'],p,result_from_dict(payload['result']))
    else:raise ValueError('Unknown worker mode')
    d=r.to_dict()
    for k,value in d.pop('model_check',{}).items():
        name='mc_'+k
        if hasattr(r,name):d[name]=value
    print(json.dumps(d,ensure_ascii=False))

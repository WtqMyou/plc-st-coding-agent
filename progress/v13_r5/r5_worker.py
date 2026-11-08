"""Private bounded worker for the r5 execution model."""
import json
import sys
import r5_judge as judge
from stbench.schema import Problem
from stbench.evaluation import result_from_dict

if __name__=='__main__':
    job=json.load(sys.stdin);p=Problem.from_dict(job['problem'])
    if job['mode']=='local':r=judge.local_tests(job['code'],p,profile=job['profile'])
    elif job['mode']=='mc':r=judge.attach_model_check(job['code'],p,result_from_dict(job['result']),job['profile'])
    else:raise ValueError('Unknown worker mode')
    d=r.to_dict();d.update({'mc_'+key:value for key,value in d.pop('model_check',{}).items()})
    print(json.dumps(d,ensure_ascii=False))

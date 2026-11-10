"""Bounded, API-free r7 model-check process."""
import json
import sys
import r7_judge as judge
from stbench.schema import Problem
from stbench.evaluation import result_from_dict

if __name__=='__main__':
    job=json.load(sys.stdin)
    result=judge.attach_model_check(job['source'],Problem.from_dict(job['problem']),result_from_dict(job['result']),job['profile'])
    data=result.to_dict();data.update({'mc_'+key:value for key,value in data.pop('model_check',{}).items()})
    print(json.dumps(data,ensure_ascii=False))

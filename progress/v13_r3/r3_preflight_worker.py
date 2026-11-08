"""Bounded private static preflight; no native or model invocation in this worker."""
from dataclasses import fields
import json
import sys
import r3_revision
from r3_judge import preflight
from stbench.schema import Problem


if __name__=='__main__':
    job=json.load(sys.stdin)
    problem,error=preflight(job['code'],Problem.from_dict(job['problem']),job['profile'])
    if error is not None:
        data=error.to_dict()
        data.update({f.name:getattr(error,f.name) for f in fields(error) if f.name.startswith('mc_')})
        print(json.dumps(dict(error=data),ensure_ascii=False),flush=True)
    else:print(json.dumps(dict(problem=problem.to_dict()),ensure_ascii=False),flush=True)

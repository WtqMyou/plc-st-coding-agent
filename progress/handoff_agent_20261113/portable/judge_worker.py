"""Package-relative functional/formal checks. No provider, API or native installation needed."""
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
job=json.load(sys.stdin)
key=job.get('release_key','latest')
if key not in ('latest','legacy'):raise ValueError('Unknown bundled judge version')
PACKAGE=ROOT/'01_原工程/progress'/('f14_agent_v14' if key=='latest' else 'f14_candidate')
RELEASE=PACKAGE/'release';sys.path.insert(0,str(RELEASE))
from stbench.schema import Problem
from stbench.evaluation import local_tests,evaluate,verification_status

def run(code,problem,formal=False):
    if formal:
        problem.mc_max_seconds=min(30,problem.mc_max_seconds)
        result=evaluate(code,problem,model_check=True,verification_after_tests=True,timeout_s=35,task_remaining_s=35)
    else:result=local_tests(code,problem)
    return dict(pid=problem.pid,compiles=result.compiles,passed=result.tests_passed,total=result.tests_total,
        verification_status=verification_status(result),model_check=result.to_dict()['model_check'])

if job['mode']=='references':
    rows=[]
    for path in sorted(RELEASE.glob('datasets/*/*.json')):
        source=PACKAGE/'reference_controls/public-medium-08.reference.st' if key=='latest' and path.stem=='public-medium-08' else path.parent/'tests'/(path.stem+'.reference.st')
        rows.append(run(source.read_text(encoding='utf-8'),Problem.load(path)))
    assert len(rows)==35 and sum(r['passed'] for r in rows)==sum(r['total'] for r in rows)==946
    result=dict(passed=True,tasks=35,cases=946,rows=rows)
else:
    pid=job['pid'];paths=list(RELEASE.glob('datasets/*/'+pid+'.json'))
    if len(paths)!=1 or Path(pid).name!=pid:raise ValueError('Unknown exact task ID')
    result=run(job['code'],Problem.load(paths[0]),job.get('formal',False))
print(json.dumps(result,ensure_ascii=False))

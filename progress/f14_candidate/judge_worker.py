"""Isolated F1.4 evaluation; never import the old r7 runtime into this process."""
import hashlib
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parent
RELEASE=ROOT/'release'
sys.path.insert(0,str(RELEASE))
from stbench.schema import Problem
from stbench.evaluation import local_tests,evaluate,feedback_for_agent,verification_status

def main():
    request=json.load(sys.stdin)
    pid=request['pid']
    paths=list(RELEASE.glob('datasets/*/'+pid+'.json'))
    if len(paths)!=1 or Path(pid).name!=pid:raise ValueError('Unknown exact task ID')
    problem=Problem.load(paths[0])
    source=request['source'];mode=request.get('mode','functional')
    if mode=='functional':result=local_tests(source,problem)
    elif mode=='bounded':
        problem.mc_max_seconds=min(problem.mc_max_seconds,30)
        result=evaluate(source,problem,model_check=True,verification_after_tests=True,
                        timeout_s=40,task_remaining_s=40)
    else:raise ValueError('Only offline functional and bounded modes are supported')
    status=verification_status(result)
    classification='unsupported_modeling' if result.mc_error.startswith('Unsupported modeling:') else 'tool_error' if result.mc_error else 'evaluated'
    result.evidence_metadata.update(data_version='STBench-F1.4',distribution='STBench-F1.4-P1',
        bridge='f14-candidate-v1',classification=classification,candidate_text_rewritten=False,
        candidate_source_sha256=hashlib.sha256(source.encode()).hexdigest(),task_json_sha256=hashlib.sha256(paths[0].read_bytes()).hexdigest(),
        native_compilation_performed_here=False,model_calls=0)
    print(json.dumps(dict(result=result.to_dict(),verification_status=status,feedback=feedback_for_agent(result)),ensure_ascii=False))

if __name__=='__main__':main()

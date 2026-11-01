"""Rejudge every saved FIFO record, including failures, under the fixed-binding contract."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from stbench.campaign import configuration,group_order,digest
from stbench.cli import problems,reference
from stbench.evaluation import atomic_json,evaluate,verification_status
from stbench.harness.engine import RunRecord
from stbench.portability import adapt,PROFILE


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--source-campaign',type=Path,required=True)
    ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    if args.out.exists():raise RuntimeError('Refusing to replace an existing replay')
    cfg=configuration('');p=next(p for p in problems() if p.pid=='public-hard-04')
    p,src,_=adapt(p,reference(p),'codesys')
    jobs=[('reference',None,src,{})]
    for fw,mid in group_order(cfg):
        path=args.source_campaign/'pilot'/(fw+'_'+mid)/(p.pid+'.json')
        if not path.exists():
            jobs.append((fw+'_'+mid,path,'',dict(original_state='not_run')));continue
        r=RunRecord.load(path);a=r.best
        details=dict(original_stop=r.stop_reason,original_error=r.error,original_model=r.model,
            original_verification=a.verification_status if a else 'not_run',
            original_platform_results=a.platform_results if a else {},
            original_cost_cny=sum(a.cost_cny for a in r.attempts))
        jobs.append((fw+'_'+mid,path,a.code if a else '',details))
    rows=[]
    for label,path,code,details in jobs:
        row=dict(label=label,source_record=str(path) if path else 'current reference',
            profile=PROFILE,judge_source_sha256=digest(),candidate_sha256=hashlib.sha256(code.encode()).hexdigest(),
            code_unchanged=True,scope='Offline rejudging; no model request and no original record replaced',**details)
        if code:
            start=time.monotonic();result=evaluate(code,p,model_check=True,timeout_s=65)
            row.update(new_judge=result.to_dict(),new_verification=verification_status(result),seconds=time.monotonic()-start)
            print(label,result.tests_passed,result.tests_total,row['new_verification'],result.mc_fixed_input_domains,flush=True)
        else:
            row['new_verification']='no_complete_candidate'
            print(label,'No complete candidate; retained as failed/unrun',flush=True)
        rows.append(row);atomic_json(args.out,rows)


if __name__=='__main__':main()

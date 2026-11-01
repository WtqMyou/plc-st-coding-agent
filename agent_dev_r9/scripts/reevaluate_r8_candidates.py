"""Recheck fixed paid R8 candidates; no model calls and no rewrite of R8 evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from stbench.campaign import digest,tasks,group_order,configuration
from stbench.harness.engine import RunRecord
from stbench.evaluation import local_tests,evaluate,atomic_json,verification_status
from request_accounting import accounting_record


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    args.out.mkdir(parents=True,exist_ok=False)
    source=digest();origin=json.loads((ROOT/'ORIGIN_R8.json').read_text(encoding='utf-8'))
    old=Path(origin['r8_campaign_root']);cfg=configuration('');rows=[];hashes={}
    changed={'public-hard-02','public-medium-08','self-easy-01','self-medium-05','self-medium-06'}
    for _,p,_ in tasks():
        for fw,mid in group_order(cfg):
            path=old/'final'/(fw+'_'+mid)/(p.pid+'.json');raw=path.read_bytes()
            hashes[str(path)]=hashlib.sha256(raw).hexdigest()
            record,_=accounting_record(RunRecord.load(path));candidate=record.best
            result=None
            if candidate and candidate.code:
                result=(evaluate(candidate.code,p,model_check=True,timeout_s=8)
                        if p.pid in changed else local_tests(candidate.code,p))
            row=dict(pid=p.pid,framework=fw,model_id=mid,r8_record_sha256=hashes[str(path)],
                candidate_sha256=candidate.code_hash if candidate else '',tests_total=len(p.test_cases),
                tests_passed=result.tests_passed if result else 0,local_compiles=result.compiles if result else False,
                formal_scope='changed-properties-target' if p.pid in changed else 'not_rechecked',
                formal_status=verification_status(result) if result and p.pid in changed else 'not_rechecked',
                r9_judge_sha256=source,native_compilation='R8 historical evidence; not rerun',
                result=result.to_dict() if result else None)
            atomic_json(args.out/(fw+'_'+mid)/(p.pid+'.json'),row);rows.append(row)
            if len(rows)%20==0:print('Fixed-code recheck',len(rows),'/ 140',flush=True)
    for path,expected in hashes.items():
        if hashlib.sha256(Path(path).read_bytes()).hexdigest()!=expected:raise RuntimeError('R8 candidate file changed')
    if digest()!=source:raise RuntimeError('R9 judge changed during fixed-code recheck')
    totals=[]
    for fw,mid in group_order(cfg):
        group=[r for r in rows if r['framework']==fw and r['model_id']==mid]
        totals.append(dict(framework=fw,model_id=mid,n=35,cases_total=sum(r['tests_total'] for r in group),
            cases_passed=sum(r['tests_passed'] for r in group),formal_targets=sum(r['pid'] in changed for r in group)))
    atomic_json(args.out/'summary.json',dict(source_sha256=source,r8_unchanged=True,rows=totals,
        generation_requests=0,scope='140 fixed candidates functional recheck; only 5 changed tasks x 4 conditions targeted formal recheck; 8s per target',
        note='Not newly generated R9 results, not a new full formal comparison'))
    print(json.dumps(totals,ensure_ascii=False),flush=True)
    return 0


if __name__=='__main__':raise SystemExit(main())

"""Copy auditable demonstration projects; never use this subset as benchmark results."""
import argparse
import json
from pathlib import Path
import shutil
import sys

ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from stbench.campaign import configuration,group_order,PILOT
from stbench.harness.engine import RunRecord
from stbench.evaluation import atomic_json


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--stage',default='final')
    ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    cfg=configuration('');campaign=Path(cfg['campaign_root']);out=args.out.resolve()
    out.relative_to((ROOT/'platform_projects').resolve());out.mkdir(parents=True,exist_ok=False)
    rows=[]
    for pid in PILOT:
        options=[]
        for fw,mid in group_order(cfg):
            path=campaign/args.stage/(fw+'_'+mid)/(pid+'.json')
            if not path.exists():continue
            r=RunRecord.load(path);a=r.best;check=path.with_name(pid+'.openplc.json')
            if not a or not a.solved or not check.exists():continue
            native=json.loads(check.read_text(encoding='utf-8'))
            if native.get('status')!='passed' or native.get('candidate_hash')!=a.code_hash:continue
            options.append((a.fully_verified,fw=='custom',mid=='deepseek-v4pro',path,a,native))
        if not options:
            rows.append(dict(pid=pid,status='no_successful_demonstration',purpose='No benchmark records removed'));continue
        _,_,_,path,a,native=max(options,key=lambda x:x[:3])
        row=dict(pid=pid,source_record=str(path),candidate_sha256=a.code_hash,verification=a.verification_status,
            tests_passed=a.tests_passed,tests_total=a.tests_total,purpose='Selected demonstration only, not aggregate performance',projects={})
        for platform,result in [('codesys',a.platform_results['codesys']),('openplc',native)]:
            src=Path(result['artifact_dir']).resolve();src.relative_to((Path(cfg['platform_root'])/'builds').resolve())
            if result['source_sha256']!=a.code_hash:raise RuntimeError('Compiler evidence does not match selected code')
            dest=out/platform/pid
            shutil.copytree(src,dest,ignore=shutil.ignore_patterns('*.opt','*.compileinfo','*.precompilecache','__pycache__','.git','*.lock'))
            row['projects'][platform]=dict(original_artifact_dir=str(src),path=dest.relative_to(ROOT).as_posix(),
                platform_identity=result['platform_identity'])
        rows.append(row)
    controls=json.loads((campaign/'native_preflight.json').read_text(encoding='utf-8'))
    for platform,checks in controls.items():
        for name in ('positive','negative'):
            result=checks[name];src=Path(result['artifact_dir']).resolve()
            src.relative_to((Path(cfg['platform_root'])/'builds').resolve())
            dest=out/platform/('control_'+name)
            shutil.copytree(src,dest,ignore=shutil.ignore_patterns('*.opt','*.compileinfo','*.precompilecache','__pycache__','.git','*.lock'))
    atomic_json(out/'project_index.json',dict(stage=args.stage,campaign=str(campaign),examples=rows,
        notice='Successful examples selected for demonstration; use full four-condition records for statistics'))
    print(json.dumps(dict(out=str(out),successful_examples=sum('projects' in r for r in rows)),ensure_ascii=False))


if __name__=='__main__':main()

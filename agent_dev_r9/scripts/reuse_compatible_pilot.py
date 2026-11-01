"""Reuse all paid pilot records only when generation, judge and dataset files are unchanged."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from stbench.campaign import configuration,snapshot,PILOT,group_order
from stbench.evaluation import atomic_json
from stbench.harness.engine import RunRecord
from pilot_provenance import ALLOWED,load_sources



def main():
    ap=argparse.ArgumentParser();ap.add_argument('--source',type=Path,required=True);args=ap.parse_args()
    cfg=configuration('');source=args.source.resolve();target=Path(cfg['campaign_root']).resolve()
    if source==target:raise RuntimeError('A separate output version is required')
    old=json.loads((source/'pilot/freeze.json').read_text(encoding='utf-8'))
    routes=json.loads((source/'routes.json').read_text(encoding='utf-8'));new=snapshot(cfg,routes)
    changed={k for k in set(old['files'])|set(new['files']) if old['files'].get(k)!=new['files'].get(k)}
    if not changed<=ALLOWED or any(old.get(k)!=new.get(k) for k in ('config','profile','routes','tasks','version')):
        raise RuntimeError('Generation/judge/data contract changed; paid pilot records cannot be reused')
    accepted=load_sources(source,old)
    ledger=json.loads(Path(cfg['budget_ledger_path']).read_text(encoding='utf-8'))
    stage=target/'pilot';stage.mkdir(parents=True,exist_ok=False)
    groups={fw+'_'+mid for fw,mid in group_order(cfg)};copies=[];excluded=[];records=0
    for path in sorted((source/'pilot').glob('*/*.json')):
        if path.name.endswith(('.timing.json','.openplc.json')):continue
        record=RunRecord.load(path)
        if path.parent.name not in groups or record.pid not in PILOT or record.max_iters!=1 or len(record.attempts)!=1:
            raise RuntimeError('Only the approved one-candidate representative pilot is reusable')
        paid=[e for e in ledger['events'] if record.started_at<=e.get('created_at',0)<=record.finished_at and
              str(e.get('request',{}).get('model','')).casefold()==record.model.casefold()]
        if not paid:
            excluded.append(dict(source=str(path),reason='No issued request in the record interval'));continue
        for a in record.attempts:
            evidence=a.judge.get('evidence_metadata',{})
            if evidence and evidence.get('judge_source_sha256') not in accepted:
                raise RuntimeError('Source pilot already contains mixed judge versions')
        records+=1
        for item in [path,path.with_name(record.pid+'.timing.json'),path.with_name(record.pid+'.openplc.json')]:
            if not item.exists():continue
            dest=stage/item.relative_to(source/'pilot');dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(item,dest);copies.append(dict(path=dest.relative_to(target).as_posix(),sha256=hashlib.sha256(item.read_bytes()).hexdigest()))
    atomic_json(stage/'freeze.json',new)
    target.mkdir(parents=True,exist_ok=True)
    for name in ['routes.json','deepseek-v4pro_protocol.json','minimax-m27_protocol.json','native_preflight.json']:
        shutil.copy2(source/name,target/name)
    prior=source/'pilot_reuse.json'
    atomic_json(target/'pilot_reuse.json',dict(source=str(source),source_freeze=old,current_source_sha256=new['judge_sha256'],
        previous_reuse=json.loads(prior.read_text(encoding='utf-8')) if prior.exists() else None,
        changed_files=sorted(changed),records=records,copied_files=copies,excluded=excluded,
        reason='Only scheduling and request-window accounting changed; one-candidate pilot prompts, transports, private judge and data are byte-identical',
        notice='Reused generation costs are already in the shared ledger; these are not new model calls. Formal results must be newly generated.'))
    print(json.dumps(dict(target=str(target),reused_paid_records=records,changed_files=sorted(changed),excluded_unissued=len(excluded)),ensure_ascii=False))


if __name__=='__main__':main()

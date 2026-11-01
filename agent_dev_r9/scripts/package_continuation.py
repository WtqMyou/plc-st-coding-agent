"""Create a new, verifiable progress archive without replacing the v2.1 release."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import time
import zipfile

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from stbench.campaign import configuration,digest
from stbench.portability import PROFILE


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True)
    ap.add_argument('--validation',type=Path,required=True)
    ap.add_argument('--include-campaign',type=Path,action='append',default=[])
    ap.add_argument('--include-evidence',type=Path,action='append',default=[])
    ap.add_argument('--include-projects',type=Path,action='append',default=[])
    ap.add_argument('--kind',choices=['continuation','final'],default='continuation')
    ap.add_argument('--analysis',type=Path)
    args=ap.parse_args()
    proof=json.loads(args.validation.read_text(encoding='utf-8'))
    if not proof.get('passed') or proof.get('source_sha256')!=digest():
        raise RuntimeError('Current source lacks passing offline validation')
    cfg=configuration('');campaign=Path(cfg['campaign_root'])
    if args.kind=='final':
        if not args.analysis:raise RuntimeError('Final package requires complete formal analysis')
        analysis=json.loads(args.analysis.read_text(encoding='utf-8'))
        exit_state=json.loads((campaign/'runner_exit.json').read_text(encoding='utf-8'))
        complete=json.loads((campaign/'campaign_completion.json').read_text(encoding='utf-8'))
        ledger=json.loads(Path(cfg['budget_ledger_path']).read_text(encoding='utf-8'))
        rows=analysis.get('rows',[])
        if (exit_state.get('state')!='completed' or complete.get('final_conditions')!=4 or
            analysis.get('stage')!='final' or not analysis.get('all_tasks_attempted') or
            analysis.get('source_sha256')!=digest() or len(rows)!=4 or
            any(r.get('n')!=35 or r.get('cases_total')!=435 or r.get('attempted')!=35 for r in rows) or
            ledger.get('halted') or ledger['spent_cny']>75):
            raise RuntimeError('Final package requires all four formal conditions, current source and an unhalted budget')
    payload={}
    for folder in ['stbench','scripts','tests','datasets','docs','platform_projects/'+PROFILE]:
        for p in (ROOT/folder).rglob('*'):
            if p.is_file() and '__pycache__' not in p.parts and p.suffix not in ('.pyc','.tmp'):
                payload['agent_dev/'+p.relative_to(ROOT).as_posix()]=p.read_bytes()
    for name in ['README.md','requirements.txt','config.example.json','config.dmxapi.json','.gitignore','requirements-analysis.txt']:
        payload['agent_dev/'+name]=(ROOT/name).read_bytes()
    for name in ['ORIGIN_R8.json','config.r9_diagnostic.json','config.r8_frozen.json']:
        if (ROOT/name).exists():payload['agent_dev/'+name]=(ROOT/name).read_bytes()
    for name in ['original_input_manifest.json','upstream_v1.2_cases.json']:
        payload['agent_dev/evidence/'+name]=(ROOT/'evidence'/name).read_bytes()
    for evidence in [args.validation.resolve().parent]+[p.resolve() for p in args.include_evidence]:
        for p in evidence.rglob('*'):
            if p.is_file():payload['agent_dev/'+p.relative_to(ROOT).as_posix()]=p.read_bytes()
    for directory in args.include_projects:
        for p in directory.resolve().rglob('*'):
            if p.is_file():payload['agent_dev/'+p.relative_to(ROOT).as_posix()]=p.read_bytes()
    for directory in [campaign]+args.include_campaign:
        for p in directory.rglob('*'):
            if p.is_file() and p.suffix in ('.json','.csv','.md','.svg','.log'):
                payload['campaign_evidence/'+directory.name+'/'+p.relative_to(directory).as_posix()]=p.read_bytes()
    payload['campaign_evidence/shared_budget_snapshot.json']=Path(cfg['budget_ledger_path']).read_bytes()
    # Fail with a filename only; never include suspected credentials in diagnostics.
    for name,raw in payload.items():
        if re.search(rb'\bsk-[A-Za-z0-9_-]{16,}',raw):
            raise RuntimeError('Credential-like content must be removed before packaging: '+name)
    manifest=dict(kind=('formal experiment evidence; failures and bounded verification limits retained'
                       if args.kind=='final' else 'development continuation, not final performance results'),profile=PROFILE,
        source_sha256=digest(),created_at=time.strftime('%Y-%m-%dT%H:%M:%S'),
        files=[dict(path=n,bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest()) for n,raw in sorted(payload.items())])
    payload['MANIFEST_continuation.json']=json.dumps(manifest,ensure_ascii=False,indent=2).encode('utf-8')
    with zipfile.ZipFile(args.out,'x',zipfile.ZIP_DEFLATED) as z:
        for name,raw in sorted(payload.items()):z.writestr(name,raw)
    with zipfile.ZipFile(args.out) as z:
        for row in manifest['files']:
            raw=z.read(row['path'])
            if len(raw)!=row['bytes'] or hashlib.sha256(raw).hexdigest()!=row['sha256']:
                raise RuntimeError('Archive verification failed: '+row['path'])
    print(json.dumps(dict(package=str(args.out.resolve()),files=len(manifest['files']),
        bytes=args.out.stat().st_size,sha256=hashlib.sha256(args.out.read_bytes()).hexdigest()),ensure_ascii=False))


if __name__=='__main__':main()

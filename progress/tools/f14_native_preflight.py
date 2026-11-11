"""Free CODESYS reference preflight, with byte- and identity-checked evidence reuse."""
from collections import Counter
import hashlib
from pathlib import Path
import sys
from types import SimpleNamespace
sys.path.insert(0,str(Path(__file__).resolve().parent))
import full_r8b_study as s

SOURCE=Path('E:/PLC_Dev/evidence/incoming_reviews/stbench_f14p1_20261111/source/STBench_F1.4-P1')
ROOT=Path('E:/PLC_Dev/evidence/incoming_reviews/f14_native_preflight_20261111')

def usable(path,identity):
    try:
        row=s.load(path);folder=path.parent
        native=s.load(folder/'codesys_result.json');job=s.load(folder/'job.json')
        source=(folder/'candidate.st').read_text(encoding='utf-8')
        if row['platform_identity']!=identity or row['returncode']!=0:return None
        if row['status'] not in ('passed','failed') or native['status']!=row['status']:return None
        if job['nonce']!=native['nonce'] or row['diagnostics']!=native['diagnostics']:return None
        if hashlib.sha256(source.encode()).hexdigest()!=row['source_sha256']:return None
        return row
    except (KeyError,ValueError,OSError,TypeError):return None

def main():
    cfg=s.config();live=Path(cfg['campaign_root']);s.verify(live);s.old.support.no_other_runner(cfg)
    ledger_path=Path(cfg['budget_ledger_path']);ledger_bytes=ledger_path.read_bytes()
    manifest=s.load(SOURCE/'冻结清单.json')
    for name,digest in manifest['sha256'].items():assert s.sha(SOURCE/name)==digest,name
    assert not ROOT.exists(),'Preflight already exists; preserve it rather than restart implicitly'
    ROOT.mkdir(parents=True);(ROOT/'cache').mkdir()
    backend=s.old.support.CodesysBackend(dict(cfg,platform_root=str(ROOT)))
    identity=backend.identity()
    assert identity==s.load(live/'native_preflight.json')['codesys']['positive']['platform_identity']
    cache={}
    for p in (Path(cfg['platform_root'])/'builds/codesys').glob('*/result.json'):
        row=usable(p,identity)
        if row:cache.setdefault(row['source_sha256'],row)
    s.atomic_json(ROOT/'baseline.json',dict(ledger_sha256=s.sha(ledger_path),events=len(s.load(ledger_path)['events']),
        spent_cny=s.load(ledger_path)['spent_cny'],source_manifest_sha256=s.sha(SOURCE/'冻结清单.json'),
        original_plan_sha256=s.sha(live/'study_plan.json'),original_package_sha256=s.sha(live/'验收包.zip'),
        controller_sha256=s.sha(__file__),platform_identity=identity))
    controls={}
    for name,code,expected in (
        ('positive','FUNCTION_BLOCK FB VAR_INPUT x:BOOL; END_VAR VAR_OUTPUT y:BOOL; END_VAR y:=x; END_FUNCTION_BLOCK','passed'),
        ('negative','FUNCTION_BLOCK FB VAR_OUTPUT y:BOOL; END_VAR y := ; END_FUNCTION_BLOCK','failed')):
        result=backend.compile(code,SimpleNamespace(pid='f14-preflight-'+name)).to_dict()
        controls[name]=result;s.atomic_json(ROOT/'controls.json',controls)
        assert result['status']==expected,'Native compiler control failed'
        assert ledger_path.read_bytes()==ledger_bytes
    rows=[]
    for path in sorted(SOURCE.glob('datasets/*/*.json')):
        problem=s.load(path);pid=path.stem;reference=path.parent/'tests'/(pid+'.reference.st')
        source=reference.read_text(encoding='utf-8');digest=hashlib.sha256(source.encode()).hexdigest()
        reused=digest in cache
        native=cache[digest] if reused else backend.compile(source,SimpleNamespace(pid='f14-ref-'+pid)).to_dict()
        rows.append(dict(pid=pid,title=problem['title'],reference_bytes_sha256=s.sha(reference),
            source_sha256=digest,source_text_rewritten=False,native_status=native['status'],
            evidence_reused=reused,native=native,tests_total=len(problem['test_cases'])))
        s.atomic_json(ROOT/'summary.json',dict(coverage_complete=False,model_calls=0,rows=rows))
        assert ledger_path.read_bytes()==ledger_bytes
        print(pid,native['status'],'reused' if reused else 'new',len(rows),'/35',flush=True)
        if native['status'] not in ('passed','failed'):
            raise RuntimeError('Shared native tool issue: preserve preflight and investigate')
    summary=dict(coverage_complete=True,model_calls=0,rows=rows,counts=dict(Counter(r['native_status'] for r in rows)),
        evidence_reused=sum(r['evidence_reused'] for r in rows),new_reference_compilations=sum(not r['evidence_reused'] for r in rows),
        tests_total=sum(r['tests_total'] for r in rows),all_references_native_passed=all(r['native_status']=='passed' for r in rows),
        model_run_admitted=False,reason='Free native preflight only; evaluator integration and experiment policy remain separate',completed_at=s.stamp())
    assert len(rows)==35 and summary['tests_total']==946
    s.atomic_json(ROOT/'summary.json',summary)
    print('COMPLETE',summary['counts'],'reused',summary['evidence_reused'],'new',summary['new_reference_compilations'],flush=True)

if __name__=='__main__':main()

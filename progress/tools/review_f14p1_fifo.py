"""Read-only audit of P1 scope, offline evidence and isolated native FIFO builds."""
import ast
import hashlib
from pathlib import Path
import sys
import zipfile
sys.path.insert(0,str(Path(__file__).resolve().parent))
import full_r8b_study as s

ARCHIVE=s.REPO/'11.11 复核2/STBench_F1.4-P1_公共FIFO平台复核_完整交付.zip'
REVIEW=Path('E:/PLC_Dev/evidence/incoming_reviews/stbench_f14p1_20261111')
SOURCE=REVIEW/'source/STBench_F1.4-P1'
BASE=Path('E:/PLC_Dev/evidence/incoming_reviews/stbench_f14_20261111/source/STBench_F1.4')
OUT=s.REPO/'progress/evidence/f14p1_fifo_review_20261111'

class WithoutDocs(ast.NodeTransformer):
    def visit_Module(self,node):return self.strip(node)
    def visit_ClassDef(self,node):return self.strip(node)
    def visit_FunctionDef(self,node):return self.strip(node)
    def strip(self,node):
        self.generic_visit(node)
        if node.body and isinstance(node.body[0],ast.Expr) and isinstance(node.body[0].value,ast.Constant) and isinstance(node.body[0].value.value,str):node.body.pop(0)
        return node

def inspect():
    assert s.sha(ARCHIVE)=='48591b735e67cab66194e8438a02eaee4c7a043fb8e90cfd96ebd44b244c3e42'
    with zipfile.ZipFile(ARCHIVE) as archive:
        for item in archive.infolist():
            if not item.is_dir():assert (SOURCE/Path(*Path(item.filename).parts[1:])).read_bytes()==archive.read(item)
    manifest=s.load(SOURCE/'冻结清单.json');assert len(manifest['sha256'])==304
    for name,digest in manifest['sha256'].items():assert s.sha(SOURCE/name)==digest,name
    protected=[p for p in BASE.rglob('*') if p.is_file() and (p.relative_to(BASE).parts[0] in ('datasets','sources') or p.name=='agent_inputs.json')]
    assert len(protected)==74
    for p in protected:assert p.read_bytes()==(SOURCE/p.relative_to(BASE)).read_bytes()
    for tree in ('datasets/public','datasets/selfmade'):
        for p in (SOURCE/tree).glob('*.json'):
            assert s.sha(p)==s.sha(BASE/tree/p.name)
    assert (SOURCE/'platform_review/平台复核与变更记录.md').read_bytes()==(ARCHIVE.parent/'平台复核与变更记录.md').read_bytes()
    for name in ('stbench/st/interp.py',):
        left=WithoutDocs().visit(ast.parse((BASE/name).read_text(encoding='utf-8')))
        right=WithoutDocs().visit(ast.parse((SOURCE/name).read_text(encoding='utf-8')))
        assert ast.dump(left,include_attributes=False)==ast.dump(right,include_attributes=False)
    index=s.load(SOURCE/'platform_review/变更文件.json')
    assert index['base_zip_sha256']=='23805581237f6da70586b26dd55899619d917310c76561b00569851819bf0952'
    for name,row in index['changes'].items():
        assert s.sha(SOURCE/name)==row['after'],name
        assert (s.sha(BASE/name) if (BASE/name).exists() else None)==row['before'],name
    full=(REVIEW/'results/verify_full.stdout.log').read_text(encoding='utf-8')
    assert 'course originals 20/20' in full and 'functional 946/946' in full and 'binding reports reproduced' in full
    assert not (REVIEW/'results/verify_full.stderr.log').read_bytes()
    native_paths=list((REVIEW/'native_runs').glob('*/summary.json'));assert len(native_paths)==1
    native=s.load(native_paths[0]);assert native['all_expectations_met'] and native['compile_only']
    statuses={name:item['build']['status'] for name,item in native['checks'].items()}
    assert statuses=={'positive-control':'passed','negative-control':'failed','course-original':'failed','dint-open-array':'passed'}
    for name,row in native['checks'].items():
        source=SOURCE/row['file'];assert s.sha(source)==row['file_bytes_sha256']
        assert hashlib.sha256(source.read_text(encoding='utf-8').encode()).hexdigest()==row['build']['source_sha256']
    app=Path(native['checks']['dint-open-array']['build']['artifact_dir'])/'candidate.app'
    assert app.is_file() and app.stat().st_size>0
    original=s.load(SOURCE/'platform_review/original/results.json')
    portable=s.load(SOURCE/'platform_review/portable/binding_results.json')
    assert original['bindings_passed']==7 and original['scans_passed']==198 and not original['counted_in_946']
    assert portable['original_interface_accepts_typed_source'] is False
    assert portable['official_case_replay_with_typed_interface']['passed']==31
    assert sum(r['passed'] for r in portable['directed'])==149 and len(portable['directed'])==5
    assert all(r['passed']==r['total'] for r in portable['directed'])
    cfg=s.config();live=Path(cfg['campaign_root']);s.verify(live)
    before=s.load(REVIEW/'results/baseline_protection.json');ledger=s.load(cfg['budget_ledger_path'])
    assert s.sha(cfg['budget_ledger_path'])==before['ledger_sha256']
    assert s.sha(live/'study_plan.json')==before['old_plan_sha256']
    assert s.sha(live/'验收包.zip')==before['old_package_sha256']
    return dict(distribution=manifest['version'],dataset_version='STBench-F1.4',archive_sha256=s.sha(ARCHIVE),
        frozen_files_verified=304,official_key_files_unchanged_from_f14=74,official_tasks=35,official_cases=946,
        original_interface_native_build='failed',dint_variant_native_build='passed',
        native_is_compile_only=True,example_plc_program_native_build_run=False,native_execution_performed=False,
        executable_interpreter_ast_unchanged=True,offline_release_passed=True,
        original_extra_bindings=7,original_extra_scans=198,dint_extra_bindings=5,dint_extra_scans=149,
        dint_official_trace_replay_passed=31,dint_is_official_original_answer=False,
        native_statuses=statuses,native_summary=native,
        dint_boot_application=dict(sha256=s.sha(app),bytes=app.stat().st_size),
        difference_from_f14=s.load(REVIEW/'results/intake.json'),baseline_protection=before,
        active_dataset_changed=False,paid_experiment_started=False,model_calls=0,
        budget_events=len(ledger['events']),accounted_cny=ledger['spent_cny'],tool_sha256=s.sha(__file__))

if __name__=='__main__':
    result=inspect()
    if sys.argv[1:]==['--check']:
        assert s.load(OUT/'review_summary.json')==result
        for name,digest in s.load(OUT/'delivery_manifest.json').get('files',{}).items():assert s.sha(OUT/name)==digest
        print('PASS unchanged F1.4 course data, P1 local checks, distinct native outcomes and original experiment protection')
    elif not sys.argv[1:]:
        OUT.mkdir(parents=True,exist_ok=True);s.atomic_json(OUT/'review_summary.json',result)
        print('P1 reviewed: 74 course files unchanged; original native failed; separate DINT FB native passed; no model calls')
    else:raise SystemExit('Usage: review_f14p1_fifo.py [--check]')

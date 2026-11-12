"""Audit completed evidence separately from an installed CLI changed since freezing."""
import json
from pathlib import Path
import sys
import zipfile
sys.path.insert(0,str(Path(__file__).resolve().parent))
import f14_no80 as n
OUT=n.REPO/'progress/evidence/f14_completion_check_20261112'

def inspect():
    cfg,root,amend=n.locations();plan=n.load(root/'study_plan.json');prepared=n.load(root/'prepared.json')
    assert n.sha(root/'study_plan.json')==prepared['plan_sha256'] and n.sha(root/'validation.json')==prepared['validation_sha256']
    assert plan['files']=={p.relative_to(n.REPO).as_posix():n.sha(p) for p in n.b.files()}
    assert plan['release_files']=={p.relative_to(n.b.RELEASE).as_posix():n.sha(p) for p in n.b.RELEASE.rglob('*') if p.is_file()}
    assert n.load(amend/'amendment_plan.json')['files']=={p.relative_to(n.REPO).as_posix():n.sha(p) for p in n.files()}
    current=n.b.audit_final(cfg,root,plan);stored=n.load(root/'final_audit.json')
    assert {k:v for k,v in current.items() if k!='at'}=={k:v for k,v in stored.items() if k!='at'}
    completed=n.load(root/'completion.json');assert completed['completed'] and completed['recorded']==140
    ledger=n.load(cfg['budget_ledger_path']);events=ledger['events'][n.HISTORY:]
    assert len(events)==completed['requests']==235 and all(e['status']=='settled' for e in events)
    assert not ledger.get('halted') and n.money(ledger['spent_cny'])<=n.money(190)
    increment=n.money(ledger['spent_cny'])-n.money(n.BASELINE)
    assert increment==sum((n.money(e['accounted_cny']) for e in events),n.money(0))
    count=0
    for file in (root/'jobs').rglob('*'):
        if file.is_file():assert file.read_bytes()==(n.MIRROR/'jobs'/file.relative_to(root/'jobs')).read_bytes();count+=1
    archive=n.MIRROR/'验收包.zip'
    with zipfile.ZipFile(archive) as zipped:
        assert zipped.testzip() is None
        for name in zipped.namelist():assert zipped.read(name)==(n.MIRROR/name).read_bytes(),name
        package_files=len(zipped.namelist())
    summary=n.load(root/'status.json');assert summary['recorded']==140
    assert all(r['recorded']==35 and r['assertions_total']==946 for r in summary['rows'])
    native=plan['native_identity']==n.b.base.old.old.support.CodesysBackend(cfg).identity()
    cli=n.b.base.old.old.cli_identity()
    return dict(historical_evidence_passed=True,completion=completed,final_audit=stored,ledger_events=len(ledger['events']),
        original_events_preserved=True,accounted_cny=ledger['spent_cny'],new_accounted_cny=float(increment),
        new_unknown_reservations=0,job_artifacts_mirrored=count,archive_files_verified=package_files,
        archive_sha256=n.sha(archive),rows=summary['rows'],credential_batches=summary['credential_batches'],
        manual_pause_at_80=False,primary_switch_checkpoint_cny=75,total_cap_cny=190,
        frozen_source_and_release_match=True,current_native_identity_match=native,
        current_cli_identity_match=cli==plan['cli_identity'],frozen_cli_identity=plan['cli_identity'],current_cli_identity=cli,
        live_environment_check_passed=native and cli==plan['cli_identity'],
        note='Historical artifacts and charges verified without rerunning models. A changed installed CLI is not treated as matching the frozen live environment.',
        audit_tool_sha256=n.sha(__file__))

if __name__=='__main__':
    result=inspect()
    if sys.argv[1:]==['--check']:assert n.load(OUT/'completed_evidence_check.json')==result
    elif not sys.argv[1:]:
        assert not OUT.exists(),'Preserve the prior inspection snapshot'
        OUT.mkdir(parents=True);n.atomic_json(OUT/'completed_evidence_check.json',result)
    else:raise SystemExit('Usage: check_f14_completed_20261112.py [--check]')
    print(json.dumps({k:result[k] for k in ('historical_evidence_passed','accounted_cny','new_accounted_cny','new_unknown_reservations','live_environment_check_passed')},ensure_ascii=False))

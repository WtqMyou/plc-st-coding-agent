"""Read-only audit and one-time publication of free F1.4 admission evidence."""
from collections import Counter
import hashlib
import json
from pathlib import Path
import shutil
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import full_r8b_study as s

BASE=Path('E:/PLC_Dev/evidence/incoming_reviews')
CANDIDATE=s.REPO/'progress/f14_candidate'
RELEASE=CANDIDATE/'release'
SOURCE=BASE/'stbench_f14p1_20261111/source/STBench_F1.4-P1'
NATIVE=BASE/'f14_native_preflight_20261111'
BRIDGE=BASE/'f14_bridge_preflight_20261111_v2'
COMPAT=BASE/'f14_reference_compatibility_20261111'
ROUTES=BASE/'f14_offline_routes_20261111'
REPAIRS=BASE/'f14_repair_routes_20261111'
OUT=s.REPO/'progress/evidence/f14_admission_preflight_20261111'

def text_sha(path):
    return hashlib.sha256(path.read_text(encoding='utf-8').encode()).hexdigest()

def patch_manifest():
    rows=[]
    for pid,changes in (
        ('public-easy-02',['Replace two infix SHR expressions with SHR(tmpBits, 1).']),
        ('public-medium-08',['Rename reserved local identifier s to ipv4WorkText (four occurrences).',
                             'Use MID(ipv4WorkText, 1, i) instead of BYTE-valued indexing.',
                             'Use UDINT#256 and INT_TO_UDINT for explicit unsigned arithmetic.'])):
        original=RELEASE/'datasets/public/tests'/(pid+'.reference.st')
        patched=CANDIDATE/'compatibility/reference_overrides'/(pid+'.reference.st')
        native=s.load(COMPAT/'native_results.json')[0]['native'] if pid=='public-easy-02' else s.load(COMPAT/(pid+'.native.json'))
        functional=s.load(COMPAT/(pid+'.functional.json'))['result']
        assert native['status']=='passed' and functional['compiles'] and functional['tests_passed']==functional['tests_total']
        assert text_sha(patched)==native['source_sha256']
        rows.append(dict(pid=pid,original_source_bytes_sha256=s.sha(original),
            original_source_text_sha256=text_sha(original),patched_source_bytes_sha256=s.sha(patched),
            patched_source_text_sha256=text_sha(patched),changes=changes,native_status='passed',
            functional_passed=functional['tests_passed'],functional_total=functional['tests_total'],
            native_result_sha256=s.sha(Path(native['artifact_dir'])/'result.json'),
            functional_result_sha256=s.sha(COMPAT/(pid+'.functional.json'))))
    return dict(kind='separate reference-only compiler compatibility patches',rows=rows,
        requirements_changed=False,interface_changed=False,tests_changed=False,model_prompt_changed=False,
        official_release_modified=False,candidate_rewriting_allowed=False,native_validation_pending=False)

def validate_native(row,expected_sha,identity):
    folder=Path(row['artifact_dir'])
    assert row['platform_identity']==identity and row['returncode']==0
    assert row['status'] in ('passed','failed') and row['source_sha256']==expected_sha
    assert text_sha(folder/'candidate.st')==expected_sha
    assert s.load(folder/'result.json')==row
    native=s.load(folder/'codesys_result.json');job=s.load(folder/'job.json')
    assert native['status']==row['status'] and native['diagnostics']==row['diagnostics']
    assert native['nonce']==job['nonce']

def budget(rows,cfg):
    specs={m['id']:m for m in cfg['models']};groups={};jobs=[]
    for row in rows:
        condition,pid=row['job_id'].split('/');framework,modelid=condition.split('_',1)
        model=specs[modelid]
        # Conservative bytes-as-token upper bounds, not a token or bill estimate.
        first=s.money(((row['upstream_message_bytes']+6144)*model['input_cny_per_million']+16384*model['output_cny_per_million'])/1e6)
        repair=s.money((65536*model['input_cny_per_million']+16384*model['output_cny_per_million'])/1e6)
        group=groups.setdefault(condition,dict(first=s.money(0),repair=s.money(0),jobs=0))
        group['first']+=first;group['repair']+=repair;group['jobs']+=1
        jobs.append(dict(job_id=row['job_id'],first_reservation_cny=float(first),repair_reservation_cny=float(repair)))
    first=sum((g['first'] for g in groups.values()),s.money(0));repair=sum((g['repair'] for g in groups.values()),s.money(0))
    spent=s.money(s.load(cfg['budget_ledger_path'])['spent_cny']);total=first+repair
    return dict(kind='draft-only budget for observed offline prompts, not a frozen live study',
        configured_prices_reused_not_requoted=True,model_specs=cfg['models'],draft_system=s.load(ROUTES/'preparation.json')['draft_common_system'],
        initial_padding_bytes=6144,repair_input_bound_including_request_padding=65536,max_output_tokens=16384,
        oversized_repair_requests_must_stop_before_send=True,accounted_cny=float(spent),cap_cny=170,checkpoint_cny=80,
        available_to_cap_cny=float(s.money(170)-spent),available_to_checkpoint_cny=float(s.money(80)-spent),
        first_reservation_cny=float(first),repair_reservation_cny=float(repair),total_reservation_cny=float(total),
        projected_total_cny=float(spent+total),fits_existing_cap=spent+total<=s.money(170),
        shortfall_cny=float(max(s.money(0),spent+total-s.money(170))),
        groups={k:dict(jobs=g['jobs'],first_cny=float(g['first']),repair_cny=float(g['repair']),total_cny=float(g['first']+g['repair'])) for k,g in groups.items()},
        jobs=jobs,budget_authorization_changed=False,ledger_changed=False,paid_requests_started=False)

def inspect():
    cfg=s.config();s.verify(Path(cfg['campaign_root']));base=s.load(NATIVE/'baseline.json')
    assert s.sha(cfg['budget_ledger_path'])==base['ledger_sha256']
    assert s.sha(Path(cfg['campaign_root'])/'study_plan.json')==base['original_plan_sha256']
    assert s.sha(Path(cfg['campaign_root'])/'验收包.zip')==base['original_package_sha256']
    manifest=s.load(RELEASE/'冻结清单.json');assert len(manifest['sha256'])==304
    files=[p for p in RELEASE.rglob('*') if p.is_file()];assert len(files)==305
    for path in files:assert path.read_bytes()==(SOURCE/path.relative_to(RELEASE)).read_bytes()
    for name,digest in manifest['sha256'].items():assert s.sha(RELEASE/name)==digest
    native=s.load(NATIVE/'summary.json');assert native['coverage_complete'] and native['counts']==dict(passed=32,failed=3)
    assert len(native['rows'])==35 and native['tests_total']==946 and native['evidence_reused']==9
    assert s.sha(s.REPO/'progress/tools/f14_native_preflight.py')==base['controller_sha256']
    failed=[]
    for row in native['rows']:
        source=RELEASE/'datasets'/('public' if row['pid'].startswith('public-') else 'selfmade')/'tests'/(row['pid']+'.reference.st')
        assert s.sha(source)==row['reference_bytes_sha256'] and text_sha(source)==row['source_sha256']
        validate_native(row['native'],row['source_sha256'],base['platform_identity'])
        if row['native_status']=='failed':failed.append(row['pid'])
    assert set(failed)=={'public-easy-02','public-hard-04','public-medium-08'}
    controls=s.load(NATIVE/'controls.json')
    for name,expected in (('positive','passed'),('negative','failed')):
        assert controls[name]['status']==expected
        validate_native(controls[name],controls[name]['source_sha256'],base['platform_identity'])
    patches=patch_manifest();assert s.load(CANDIDATE/'compatibility/reference_patch_manifest.json')==patches
    for pid,row in (('public-easy-02',s.load(COMPAT/'native_results.json')[0]['native']),('public-medium-08',s.load(COMPAT/'public-medium-08.native.json'))):
        validate_native(row,text_sha(CANDIDATE/'compatibility/reference_overrides'/(pid+'.reference.st')),base['platform_identity'])
    bridge=s.load(BRIDGE/'completion.json');assert bridge['passed'] and bridge['reference_tasks']==35 and bridge['reference_cases']==946
    for file,key in (('bridge.py','bridge_sha256'),('judge_worker.py','worker_sha256')):assert s.sha(CANDIDATE/file)==bridge[key]
    assert s.sha(s.REPO/'progress/tools/f14_bridge_preflight.py')==bridge['controller_sha256']
    refs=s.load(BRIDGE/'reference_rows.json');assert len(refs)==35 and sum(r['passed'] for r in refs)==946
    assert all(r['passed']==r['total'] for r in refs)
    route=s.load(ROUTES/'routes.json');prep=s.load(ROUTES/'preparation.json');rows=route['rows']
    assert route['completed'] and len(rows)==len({r['job_id'] for r in rows})==140 and route['real_cli_invocations']==70
    assert s.sha(s.REPO/'progress/tools/f14_offline_routes.py')==prep['controller_sha256']
    assert s.sha(CANDIDATE/'codex_transport.py')==prep['adapter_sha256']
    prompts=s.load(RELEASE/'agent_inputs.json');counts=Counter();assertions=Counter()
    for row in rows:
        condition,pid=row['job_id'].split('/');counts[condition]+=1;assertions[condition]+=row['tests_passed']
        request=s.load(ROUTES/'requests'/condition/(pid+'.json'));messages=request['messages']
        serialized=json.dumps(messages,ensure_ascii=False).encode()
        assert len(serialized)==row['upstream_message_bytes'] and hashlib.sha256(serialized).hexdigest()==row['upstream_messages_sha256']
        assert any(m['role']=='user' and m['content']==prompts[pid]['user'] for m in messages)
        assert row['external_requests']==request['external_requests']==0 and row['gateway_fixture_requests']==1
    assert len(counts)==4 and set(counts.values())=={35} and set(assertions.values())=={946}
    repair=s.load(REPAIRS/'completion.json');assert repair['passed'] and len(repair['rows'])==12
    assert Counter(r['feedback_kind'] for r in repair['rows'])==dict(compile=4,functional=4,**{'formal-synthetic':4})
    assert s.sha(s.REPO/'progress/tools/f14_repair_routes.py')==repair['controller_sha256'] and s.sha(CANDIDATE/'codex_transport.py')==repair['adapter_sha256']
    for row in repair['rows']:
        saved=s.load(REPAIRS/(row['label']+'.json'));feedback=saved['expected_feedback'].replace('\r\n','\n')
        assert any(feedback in m['content'].replace('\r\n','\n') for m in saved['messages'])
        assert '期望' not in feedback and '实际' not in feedback and saved['external_requests']==0
    probe=s.load(REPAIRS/'synthetic_formal_probe.json')
    assert probe['synthetic'] and not probe['counted_in_35_tasks']
    assert probe['before']['tests_passed']==probe['before']['tests_total']==1
    assert probe['before']['model_check']['violations'] and not probe['after']['model_check']['violations']
    assert all(item['ledger_sha256']==base['ledger_sha256'] for item in (bridge,prep,route,repair))
    ledger=s.load(cfg['budget_ledger_path']);assert len(ledger['events'])==653 and ledger['spent_cny']==61.076553
    code_files=[p for p in CANDIDATE.rglob('*.py') if 'release' not in p.relative_to(CANDIDATE).parts]
    return dict(free_checks_passed=True,live_model_admitted=False,paid_requests=0,official_release_files_verified=305,
        official_reference_native=dict(passed=32,failed=3,total=35,failed_ids=failed,reused=9,new_reference_compilations=26),
        separate_reference_patches=patches,with_two_reference_patches_native_passed=34,original_fifo_still_native_unsupported=True,
        isolated_reference_tasks=35,isolated_reference_cases_passed=946,initial_fake_routes=140,repair_fake_routes=12,
        real_cli_invocations=76,synthetic_formal_probe_in_benchmark=False,functional_execution_is_python_interpreter=True,
        original_paid_model_results_replaced=False,active_judge_changed=False,budget_events=653,accounted_cny=61.076553,
        baseline=base,bridge_completion=bridge,route_preparation=prep,repair_completion=repair,
        candidate_python_sha256={p.relative_to(s.REPO).as_posix():s.sha(p) for p in code_files},
        budget_draft=budget(rows,cfg),audit_tool_sha256=s.sha(__file__))

def publish():
    assert not OUT.exists(),'Preserve existing published evidence'
    s.atomic_json(CANDIDATE/'compatibility/reference_patch_manifest.json',patch_manifest())
    result=inspect();OUT.mkdir(parents=True)
    for source,label in ((NATIVE,'native'),(BRIDGE,'bridge'),(COMPAT,'compatibility'),(ROUTES,'initial_routes'),(REPAIRS,'repair_routes')):
        for file in source.glob('*.json'):
            target=OUT/label/file.name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(file,target)
    shutil.copytree(ROUTES/'requests',OUT/'initial_routes/requests')
    builds={r['pid']:r['native'] for r in s.load(NATIVE/'summary.json')['rows']}
    builds.update({'control-'+k:v for k,v in s.load(NATIVE/'controls.json').items()})
    builds['patched-public-easy-02']=s.load(COMPAT/'native_results.json')[0]['native']
    builds['patched-public-medium-08']=s.load(COMPAT/'public-medium-08.native.json')
    builds['ipv4-rename-only-diagnostic']=s.load(COMPAT/'native_results.json')[1]['native']
    for label,row in builds.items():
        for name in ('candidate.st','job.json','result.json','codesys_result.json','codesys_stdout.log','codesys_stderr.log'):
            source=Path(row['artifact_dir'])/name
            if source.is_file():
                target=OUT/'native_artifacts'/label/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
    s.atomic_json(OUT/'admission_summary.json',result)
    s.atomic_json(OUT/'预算草案.json',result['budget_draft'])
    s.atomic_json(OUT/'evidence_manifest.json',dict(files={p.relative_to(OUT).as_posix():s.sha(p) for p in OUT.rglob('*') if p.is_file()}))
    return result

if __name__=='__main__':
    if sys.argv[1:]==['--check']:
        result=inspect();assert result==s.load(OUT/'admission_summary.json')
        for name,digest in s.load(OUT/'evidence_manifest.json')['files'].items():assert s.sha(OUT/name)==digest
    elif not sys.argv[1:]:result=publish()
    else:raise SystemExit('Usage: audit_f14_admission.py [--check]')
    print(json.dumps({k:result[k] for k in ('free_checks_passed','paid_requests','official_reference_native','accounted_cny')},ensure_ascii=False))

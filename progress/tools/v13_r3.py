"""Offline diagnostics for the judge-only r3 revision. No model client entrypoint."""
from pathlib import Path
import argparse
import importlib.util
import json
import re
import subprocess
import sys

REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO/'progress/v13_r3'))
import r3_revision as v
OUT=REPO/'progress/evidence/v13_r3_20261108'
SCORES=REPO/'progress/evidence/v13_r3_rescore_20261108b'
LEDGER=Path('E:/PLC_Dev/evidence/dmxapi_budget_75.json')


def load(path):return json.loads(path.read_text('utf-8'))
def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes((json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode())


def no_frozen_write():
    if (v.ROOT/'snapshot_manifest.json').exists():raise RuntimeError('r3 is frozen; use check or create a new revision')


def native(platform,kind='core'):
    no_frozen_write()
    from native_probes import examples
    from stbench.platforms import CodesysBackend,OpenPLCBackend
    from stbench.evaluation import atomic_json
    ledger=Path('E:/PLC_Dev/evidence/dmxapi_budget_75.json');before=v.digest(ledger.read_bytes())
    rows=examples(kind);cfg=load(v.ENGINE/'config.example.json');assert not cfg['models'] and not cfg['live_enabled']
    path=OUT/(platform+('_indexing' if kind=='indexing' else '')+'_probes.json');assert not path.exists(),'Do not overwrite native observations'
    if platform=='codesys':
        spec=importlib.util.spec_from_file_location('r3_native_batch',v.ENGINE/'scripts/codesys_reference_batch.py')
        batch=importlib.util.module_from_spec(spec);spec.loader.exec_module(batch)
        batch.problems=lambda:[r['problem'] for r in rows]
        batch.reference=lambda p:next(r['code'] for r in rows if r['problem'].pid==p.pid)
        from stbench.st.driver import StageResult
        from stbench.st.typecheck import check_st
        batch.local_tests=lambda code,p:StageResult(compiles=check_st(code).ok,tests_total=0)
        batch.config=lambda _:cfg
        batch.export_summary=lambda _old,records:atomic_json(path,records)
        sys.argv=['r3-native-probes']
        batch.main()  # Expected native failures are the subject of this audit.
        results=load(path)
    else:
        backend=OpenPLCBackend(cfg);results=[]
        for row in rows:
            result=dict(pid=row['problem'].pid,**backend.compile(row['code'],row['problem']).to_dict())
            results.append(result);write(path,results);print(result['pid'],result['status'],flush=True)
    for row in rows:
        record=next(r for r in results if r['pid']==row['problem'].pid)
        expected=row['expected'].get(platform) if isinstance(row['expected'],dict) else row['expected']
        if expected is not None:assert record['status']==expected,(platform,row['problem'].pid,record['status'])
    assert v.digest(ledger.read_bytes())==before
    print(platform,'native observations completed; model calls 0',flush=True)


def verify():
    no_frozen_write()
    import r3_judge as judge
    from native_probes import examples
    from stbench.platforms import CodesysBackend,OpenPLCBackend
    before=v.digest(LEDGER.read_bytes());cfg=load(v.ENGINE/'config.example.json')
    matrix=[];identities={}
    for cls in (CodesysBackend,OpenPLCBackend):
        backend=cls(cfg);identity=backend.identity();identities[backend.name]=identity
        for kind in ('core','indexing'):
            path=OUT/(backend.name+('_indexing' if kind=='indexing' else '')+'_probes.json')
            records=load(path);fixtures=examples(kind);assert len(records)==len(fixtures)
            for probe in fixtures:
                row=next(r for r in records if r['pid']==probe['problem'].pid)
                assert row['source_sha256']==v.digest(probe['code'].encode()) and row['platform_identity']==identity
                assert row['status'] in ('passed','failed')
                expected=probe['expected'].get(backend.name) if isinstance(probe['expected'],dict) else probe['expected']
                if expected is not None:assert row['status']==expected
                matrix.append(dict(platform=backend.name,pid=row['pid'],status=row['status'],source_sha256=row['source_sha256'],
                    evidence_file=path.relative_to(REPO).as_posix(),artifact_dir=row['artifact_dir']))
    assert len(matrix)==20
    write(OUT/'native_matrix.json',dict(observations=matrix,
        note='OpenPLC candidate acceptance refuted the initial both-platform rejection assumption; original observations retained. Native acceptance is not a claim about runtime correctness.'))
    suites=[]
    for pattern in ('test_v13_r2.py','test_v13_r3.py'):
        result=subprocess.run([sys.executable,'-B','-X','utf8','-m','unittest','discover','-s','progress/tests','-p',pattern,'-q'],
            cwd=REPO,capture_output=True,text=True,encoding='utf-8',timeout=90)
        (OUT/(pattern+'.log')).write_bytes((result.stdout+'\n'+result.stderr).encode());assert result.returncode==0,result.stderr[-1500:]
        suites.append(dict(pattern=pattern,tests=int(re.search(r'Ran (\d+) tests?',result.stderr)[1]),passed=True))
    rows=[]
    for p in v.problems():
        q,source,_=v.adapt(p);r=judge.local_tests(source,q)
        rows.append(dict(pid=p.pid,compiles=r.compiles,tests_total=r.tests_total,tests_passed=r.tests_passed,
            errors=r.compile_errors,failures=[c.to_dict() for c in r.cases if not c.passed]))
    assert all(r['compiles'] and r['tests_passed']==r['tests_total'] for r in rows)
    prior=load(REPO/'progress/evidence/v13_r2_20261108/offline.json')
    # Data, references and formula policy are unchanged. Existing formula and
    # native-reference evidence is reused by binding hashes, never relabeled fresh.
    for p,row in zip(v.problems(),prior['rows'],strict=True):
        assert p.pid==row['pid']
        if 'formula_replay' in row:
            assert all(s.get('holds') and not s.get('error') for s in row['formula_replay']['formulas'])
    native_reference=prior['native_evidence']
    for entry in native_reference:
        original_path=REPO/entry['source']
        assert v.digest(original_path.read_bytes())==entry['source_sha256']
        assert all(row['platform_identity']==identities[entry['platform']] for row in load(original_path))
        for p in v.problems():
            _,code,_=v.adapt(p,platform=entry['platform'])
            assert next(r for r in entry['entries'] if r['pid']==p.pid)['source_sha256']==v.digest(code.encode())
    # Historical results have exactly the same candidate bytes as the fresh audit.
    history=Path('E:/PLC_Dev/evidence/real_experiments/campaign_75_window_r8/final/codex_minimax-m27/public-medium-08.json')
    record=load(history);attempt=record['attempts'][record['best_attempt']]
    candidate_hash=v.digest(v.historical_candidate().encode())
    assert v.digest(attempt['code'].encode())==candidate_hash
    codesys=attempt['platform_results']['codesys'];assert codesys['source_sha256']==candidate_hash and codesys['status']=='failed'
    historical_openplc=load(history.with_name('public-medium-08.openplc.json'))
    assert historical_openplc['source_sha256']==candidate_hash and historical_openplc['status']=='passed'
    write(OUT/'root_cause.json',dict(candidate_sha256=candidate_hash,original_record_sha256=v.digest(history.read_bytes()),
        cause='String-returning builtins lost their type; arithmetic on strings passed static checks and raised Python TypeError.',
        historical_codesys=codesys,historical_openplc=historical_openplc,
        classification='CODESYS profile candidate_static_error; OpenPLC arithmetic outside verified local model',
        candidate_modified=False,old_records_modified=False))
    assert v.digest(LEDGER.read_bytes())==before
    write(OUT/'offline.json',dict(version=v.VERSION,data_version=v.DATA_VERSION,passed=True,cases=531,cases_passed=531,
        rows=rows,suites=suites,judge_version=judge.JUDGE_VERSION,static_profile='codesys',
        raw_ltl=prior['raw_ltl'],runtime_ltl=prior['runtime_ltl'],total_properties=prior['total_properties'],
        native_results_reused=True,native_evidence=native_reference,native_probes_count=20,
        formula_evidence=dict(source='progress/evidence/v13_r2_20261108/offline.json',sha256=v.digest((REPO/'progress/evidence/v13_r2_20261108/offline.json').read_bytes()),mode='unchanged data/reference/formula policy'),
        model_calls=0,ledger_unchanged=True,ledger_sha256=before,human_review='r2_pending'))
    print('PASS r3 verify: 531/531, tests',sum(x['tests'] for x in suites),'native observations 20',flush=True)


def rescore():
    no_frozen_write();import r3_judge as judge
    from stbench.platforms import CodesysBackend
    assert not SCORES.exists(),'Use a new output directory'
    before=v.digest(LEDGER.read_bytes());path=REPO/'progress/evidence/v13_r2_rescore_20261108/rescore.json';baseline=load(path)
    problems={p.pid:p for p in v.problems()};groups={};details=[];boundaries=[]
    native_backend=CodesysBackend(load(v.ENGINE/'config.example.json'))
    for item in baseline['details']:
        group,pid=item['group'],item['pid']
        row=groups.setdefault(group,dict(group=group,tasks=35,old_cases=531,new_cases=531,old_solved=0,new_solved=0,
            old_passed=0,new_passed=0,lost=[],gained=[],tool_errors=[],compile_rejections=[]))
        artifact=REPO/'progress/evidence/v13_rescore_20261108b/candidates'/group/(pid+'.st')
        code=artifact.read_bytes() if artifact.exists() else b'';assert v.digest(code)==item['code_sha256']
        result=None;error=''
        if code:
            q,_,_=v.adapt(problems[pid])
            try:
                result=judge.local_tests(code.decode(),q,profile='codesys')
                if result.evidence_metadata.get('classification')=='unsupported_modeling':
                    result=judge.resolve_native(result,code.decode(),q,(native_backend,))
                    boundaries.append(dict(group=group,pid=pid,source_sha256=item['code_sha256'],
                        result=result.platform_results,classification=result.evidence_metadata.get('classification')))
                    write(OUT/'native_boundaries.json',boundaries)
            except Exception as exc:error=f'{type(exc).__name__}: {exc}'
        classification=result.evidence_metadata.get('classification') if result else None
        if result is not None and result.evidence_metadata.get('test_contract_valid') is False:
            raise RuntimeError('Invalid test data cannot be counted as a model error')
        old_ok=item['r2_solved'];new_ok=bool(result and result.compiles and result.all_tests_passed)
        old_pass=item['r2']['tests_passed'] if item['r2'] else 0;new_pass=result.tests_passed if result else 0
        row['old_solved']+=int(old_ok);row['new_solved']+=int(new_ok);row['old_passed']+=old_pass;row['new_passed']+=new_pass
        if old_ok and not new_ok:row['lost'].append(pid)
        if new_ok and not old_ok:row['gained'].append(pid)
        if error or classification=='unsupported_modeling':row['tool_errors'].append(pid)
        if classification in ('candidate_static_error','candidate_native_error'):row['compile_rejections'].append(pid)
        details.append(dict(group=group,pid=pid,code_sha256=item['code_sha256'],frozen_attempt_index=item['frozen_attempt_index'],
            r2_solved=old_ok,r3_solved=new_ok,r2_passed=old_pass,r3=result.to_dict() if result else None,
            r2_error=item['r2_error'],r3_error=error,classification=classification))
    assert len(details)==140 and v.digest(LEDGER.read_bytes())==before
    write(SCORES/'rescore.json',dict(version=v.VERSION,data_version=v.DATA_VERSION,baseline_version='v1.3-review-r2',
        baseline_label='r2 本地整题',current_label='r3 本地整题',static_profile='codesys',rows=list(groups.values()),details=details,
        baseline_sha256=v.digest(path.read_bytes()),fixed_candidates=True,model_calls=0,ledger_unchanged=True,
        scope='CODESYS static profile, same frozen r2 data and R8 candidates; local post-hoc scoring, not new model generation or runtime PLC validation'))
    lines=['# r2 → r3 固定候选事后评分','','同一531条用例、同一R8冻结候选；仅裁判类型闸门变化，主口径为CODESYS。','',
        '| 组别 | r2整题 | r3整题 | r2用例 | r3用例 | r3工具未决 |','| --- | ---: | ---: | ---: | ---: | ---: |']
    for row in groups.values():
        lines.append(f'| {row["group"]} | {row["old_solved"]}/35 | {row["new_solved"]}/35 | {row["old_passed"]}/531 | {row["new_passed"]}/531 | {len(row["tool_errors"])} |')
    lines+=['','原字符串候选未修改。CODESYS原生拒绝，OpenPLC入口接受的记录同时保留；后者没有被改写为失败。OpenPLC未建模表达式单列为未决，不用CODESYS类型规则冒充OpenPLC结论。',
        '本表不替换R8正式结果，不计为模型准确率提升，不执行新的付费生成。']
    (SCORES/'重评分结果.md').write_bytes(('\n'.join(lines)+'\n').encode())
    print(json.dumps(list(groups.values()),ensure_ascii=False),flush=True)


def freeze():
    no_frozen_write();v.verify_parent();v.r2.verify_parent();v.r2.r1.verify_engine()
    proof=load(OUT/'offline.json');scores=load(SCORES/'rescore.json')
    assert proof['passed'] and len(scores['details'])==140
    assert v.digest(LEDGER.read_bytes())==proof['ledger_sha256']
    target=next(r for r in scores['details'] if r['group']=='codex_minimax-m27' and r['pid']=='public-medium-08')
    assert target['classification']=='candidate_static_error' and not target['r3_error']
    acceptance=dict(version=v.VERSION,data_version=v.DATA_VERSION,technical_passed=True,cases=531,cases_passed=531,
        tests=sum(s['tests'] for s in proof['suites']),suites=proof['suites'],native_observations=20,
        native_boundary_runs=len(load(OUT/'native_boundaries.json')) if (OUT/'native_boundaries.json').exists() else 0,
        primary_static_profile='codesys',posthoc_records=140,tool_unresolved=sum(len(r['tool_errors']) for r in scores['rows']),
        candidate_unchanged=True,parent_versions_unchanged=True,native_reference_evidence_reused=70,
        formula_evidence_reused=True,model_calls=0,ledger_unchanged=True,spent_cny=load(LEDGER)['spent_cny'],
        ledger_events=len(load(LEDGER)['events']),human_review='r2_pending')
    write(OUT/'acceptance.json',acceptance)
    files=[p for p in v.ROOT.rglob('*') if p.is_file() and '__pycache__' not in p.parts]
    files += [Path(__file__),REPO/'progress/tests/test_v13_r3.py']
    write(v.ROOT/'snapshot_manifest.json',dict(version=v.VERSION,data_version=v.DATA_VERSION,
        files={p.relative_to(REPO).as_posix():v.digest(p.read_bytes()) for p in sorted(files)},
        evidence_sha256={p.relative_to(REPO).as_posix():v.digest(p.read_bytes()) for p in sorted(OUT.rglob('*')) if p.is_file() and p.name!='status_viewer.json'},
        rescore_sha256=v.digest((SCORES/'rescore.json').read_bytes()),acceptance_sha256=v.digest((OUT/'acceptance.json').read_bytes())))
    print(json.dumps(acceptance,ensure_ascii=False),flush=True)


def check():
    v.verify_parent();v.r2.verify_parent();v.r2.r1.verify_engine();m=load(v.ROOT/'snapshot_manifest.json')
    for name,expected in {**m['files'],**m['evidence_sha256']}.items():assert v.digest((REPO/name).read_bytes())==expected,name
    assert v.digest((SCORES/'rescore.json').read_bytes())==m['rescore_sha256']
    assert v.digest((OUT/'acceptance.json').read_bytes())==m['acceptance_sha256']
    print('PASS r3, r2, r1, engine and evidence hashes')


if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('command',choices=['native','verify','rescore','freeze','check']);ap.add_argument('--platform',choices=['codesys','openplc']);ap.add_argument('--set',choices=['core','indexing'],default='core')
    args=ap.parse_args()
    if args.command=='native':
        if not args.platform:ap.error('native requires --platform')
        native(args.platform,args.set)
    else:globals()[args.command]()

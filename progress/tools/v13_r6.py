"""Build and verify an offline, provenance-preserving November 10 revision."""
import argparse
from collections import Counter, defaultdict
import copy
import hashlib
from html import escape
import json
from pathlib import Path
import re
import subprocess
import sys
import zipfile

REPO = Path(__file__).resolve().parents[2]
ROOT = REPO/'progress/v13_r6'
OUT = REPO/'progress/evidence/v13_r6_20261110'
SCORES = REPO/'progress/evidence/v13_r6_rescore_20261110'
LEDGER = Path('E:/PLC_Dev/evidence/dmxapi_budget_75.json')
sys.path.insert(0, str(REPO/'progress/v13_r5'))
import r5_revision as previous
import r5_judge
from conversions import runtime, checked
from stbench.schema import Problem, Spec
from stbench.st.frontend import compile_st
from stbench.st.driver import _plain
from stbench.st.interp import _match
from stbench.ltl import evaluate as ltl_evaluate
from stbench.spec_policy import formula_names
from stbench.spec_observers import observer_for
from stbench.platforms import CodesysBackend, OpenPLCBackend


def load(path): return json.loads(path.read_text('utf-8-sig'))
def sha(raw): return hashlib.sha256(raw).hexdigest()
def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes((json.dumps(value, ensure_ascii=False, indent=2)+'\n').encode())
def mutable(): assert not (ROOT/'snapshot_manifest.json').exists(), 'r6 frozen; use a new revision'
def revision():
    sys.path.insert(0, str(ROOT))
    import r6_revision
    return r6_revision


def group_cases(problem):
    groups = defaultdict(list)
    for case in problem.test_cases:
        mode = case.mode or problem.case_mode
        groups[(mode, case.tc_id if mode=='single' else '')].append(case)
    return groups


def traces(source, problem):
    """Replay every scan and init, retaining interface-only observer snapshots."""
    parsed, _ = checked(compile_st(source), 'codesys')
    assert parsed.ok, problem.pid
    engine = runtime('codesys')
    observer = observer_for(problem.provenance.get('r9_spec_policy', {}).get('observer'))
    names = {v.name.lower() for v in problem.variables}
    rows = []
    for (mode, _), cases in group_cases(problem).items():
        machine = engine.Interpreter(parsed.pou, parsed.structs)
        initial = None
        frames, ids = [], []
        for c in cases:
            for k, value in c.init.items(): machine.set_var(k, value)
            if initial is None:
                initial = copy.deepcopy({k:v for k,v in engine.modelcheck.snapshot(machine).items() if k in names})
                if observer: initial.update(observer(initial, None, True))
            for k, value in c.const_inputs.items(): machine.set_var(k, value)
            constants = {k.lower() for k in c.const_inputs}
            inputs = {k.lower():value for k,value in c.inputs.items()}
            for variable in problem.inputs:
                k = variable.name.lower()
                if k in inputs: machine.set_var(k, inputs[k])
                elif k not in constants and machine.types.get(k,'').upper()=='BOOL': machine.set_var(k,False)
            for _ in range(max(1,c.cycles)):
                machine.scan()
                frame = copy.deepcopy({k:v for k,v in engine.modelcheck.snapshot(machine).items() if k in names})
                if observer: frame.update(observer(frame, frames[-1] if frames else initial, False))
                frames.append(frame); ids.append(c.tc_id)
            assert all(_match(machine.get_var(k),expected) for k,expected in c.expected.items()), (problem.pid,c.tc_id,'audit trace differs from functional replay')
        rows.append(dict(group=mode,initial=initial,frames=frames,ids=ids,
                         atom=engine.modelcheck._atom_evaluator(machine.types,parsed.structs)))
    return rows


def formula_verdict(formula, sequences, allowed):
    try:
        missing = sorted(formula_names(formula)-allowed)
        if missing: return dict(status='unbound',names=missing)
        unresolved=None
        for seq in sequences:
            verdict = ltl_evaluate(formula, seq['frames'], seq['atom'], init_snapshot=seq['initial'])
            if verdict.inconclusive or not verdict.holds:
                at = verdict.counterexample_at
                result=dict(status='inconclusive' if verdict.inconclusive else 'violated',group=seq['group'],
                    scan=at,case=seq['ids'][at-1] if at and at<=len(seq['ids']) else None,reason=verdict.reason)
                if not verdict.inconclusive:return result
                unresolved=unresolved or result
        if unresolved:return unresolved
        return dict(status='hold_on_test_traces')
    except Exception as exc:
        return dict(status='unmodeled',reason=type(exc).__name__+': '+str(exc))


def build(incoming):
    mutable()
    assert incoming.name == 'STBench_F1.3'
    before = sha(LEDGER.read_bytes())
    archives = []
    for path in sorted((REPO/'11.10意见').iterdir()):
        row = dict(name=path.name,bytes=path.stat().st_size,sha256=sha(path.read_bytes()))
        if path.suffix=='.zip':
            with zipfile.ZipFile(path) as z: row['members']=len(z.infolist())
        archives.append(row)
    if (ROOT/'ORIGIN_R5.json').exists():
        origin=load(ROOT/'ORIGIN_R5.json')
        assert origin['incoming_archives']==archives, 'Different handoff: use a new revision'
        assert origin['ledger_sha256']==before, 'Ledger changed during draft build'
    write(ROOT/'ORIGIN_R5.json',dict(parent_git='02f6f37b712f7c64983585d6b1a9edcb2d6f8096',
        parent_manifest_sha256=sha((REPO/'progress/v13_r5/snapshot_manifest.json').read_bytes()),
        incoming_archives=archives,ledger_sha256=before,date='2026-11-10',
        live_enabled=False,upstream_execution='separate local replay; no provider calls',
        upstream_formal_claim='320 bounded properties is the sender claim; quick replay did not rerun SMT solvers'))
    # Preserve the actual raw JSON/ST and explanatory documents, without importing
    # the sender's runtime, paid runners, providers or source-specific proof engines.
    members = [*incoming.glob('datasets/*/*-*.json'),*incoming.glob('datasets/*/tests/*.st')]
    members += [incoming/n for n in ('README.md','最终复核结果.md','35题逐题修改说明.md','审核与修改记录.md',
        '全库逐题反例审核.md','有界检查逐题复核.md')]
    members += [incoming/'review'/n for n in ('peer_baseline.json','coverage.json','release_controls.json')]
    with zipfile.ZipFile(REPO/'11.10意见/STBench_F1.3_全库复核_最终工程.zip') as archive:
        for src in members:
            assert src.read_bytes()==archive.read('STBench_F1.3/'+src.relative_to(incoming).as_posix()),src
    frozen = {}
    for src in members:
        relative = src.relative_to(incoming)
        target = ROOT/'upstream'/relative
        target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(src.read_bytes())
        frozen[relative.as_posix()] = sha(src.read_bytes())
    write(ROOT/'upstream_manifest.json',dict(files=frozen,untrusted_source=True,
        note='Evidence is reviewed before adoption; upstream scripts are not installed as our judge.'))
    decisions=[]; spec_decisions=[]
    for original in previous.problems():
        p, source, _ = previous.adapt(original)
        d = load(incoming/'datasets'/original.source/(original.pid+'.json'))
        d['provenance']['human_process_review']=dict(status='pending',reviewer='刘晏铭',approved=False)
        for c in d['test_cases']:
            mode=c.get('mode') or d.get('case_mode','single')
            c['mode']='single' if mode=='single' else 'sequence:peer:'+c.get('group','default')
        peer, _, _ = previous.adapt(Problem.from_dict(d),source=previous.reference(original))
        if p.pid in ('public-easy-05','public-medium-06'):
            # Make the already-used scan-count timing profile visible in the
            # effective contract; keep raw_text and the TIME interface intact.
            p.requirements=peer.requirements
            incoming_vars={x.name.lower():x for x in peer.variables}
            for variable in p.variables:
                match=incoming_vars.get(variable.name.lower())
                if match and match.data_type==variable.data_type and match.direction==variable.direction:
                    variable.description=match.description
        if p.pid=='self-hard-02':
            for variable in p.variables:
                if variable.name=='elapsed':variable.description='本批次已计入的扫描拍数，启动拍为0'
                if variable.name=='maxDuration':variable.description='本拍超时门槛，正整数扫描拍数'
        # Reference corrections are tied to existing requirements, with the INT
        # upper-limit policy stated explicitly rather than inferred from a score.
        if p.pid in ('self-easy-02','self-medium-01','self-medium-04'):
            ref=(incoming/'datasets'/original.source/'tests'/(p.pid+'.reference.st')).read_text('utf-8')
            _, source, _=previous.adapt(original,source=ref)
        if p.pid=='self-easy-02':
            p.requirements=d['requirements']
            s=next(s for s in p.specs if s.sid=='S1')
            s.ltl='G(tankLevel >= 85.0 -> alarmHigh)'
            s.text='高液位危险与复位同拍也必须报警，危险条件优先。'
        if p.pid=='self-medium-01':
            next(s for s in p.specs if s.sid=='S1').text='空槽装载判为非法并将loadedID清零；生产运行中不接受装载。'
        if p.pid=='self-medium-04':
            p.requirements+='\nr6明确INT满量程约定：计数到32767后保持，继续完成灌装握手；合法复位后重新计数。人工工艺复审待确认。'
        # Do not change the TIME interface, pump lag selection or gate behavior
        # by copying a different problem under its old identifier.
        defer_all=p.pid in ('public-easy-04','self-medium-03')
        reasons={'public-easy-04':'毫秒接口与历史TIME/扫描适配契约不同，留作独立后续版本。',
                 'self-medium-03':'遇障后停机/反向、双键复位规则与r4题面存在冲突，等待人工确认。'}
        # Case identifiers from each source retain a stable namespace. Existing
        # 583 assertions remain byte-for-byte identical as dictionaries.
        old_cases=copy.deepcopy(p.test_cases)
        existing_single={json.dumps({k:c.to_dict().get(k) for k in ('inputs','const_inputs','init','expected','cycles')},sort_keys=True)
                         for c in old_cases if (c.mode or p.case_mode)=='single'}
        old_sequences=[cs for (mode,_),cs in group_cases(p).items() if mode!='single']
        signature=lambda cs: json.dumps([{k:c.to_dict().get(k) for k in ('inputs','const_inputs','init','expected','cycles')} for c in cs],sort_keys=True)
        old_sequence_signatures={signature(cs) for cs in old_sequences}
        admitted=[]; task_decisions=[]
        for (mode,_), cases in group_cases(peer).items():
            decision='adopt';reason='与现行接口和控制要求相容，整段保留原始轨迹。'
            if defer_all: decision='defer';reason=reasons[p.pid]
            elif p.pid=='self-hard-04' and mode=='sequence:peer:seq':
                decision='defer';reason='整段seq含2→3需求时重选备泵的p14，与r4保持备泵规则冲突；不抽掉中间拍。'
            transformed=copy.deepcopy(cases)
            for c in transformed:
                c.tc_id='peer-'+c.tc_id
                if p.pid=='self-hard-03' and isinstance(c.expected.get('fifo'),dict):
                    prefix=c.expected['fifo']
                    assert set(prefix)=={'$prefix'} and isinstance(prefix['$prefix'],list)
                    values=prefix['$prefix'];assert len(values)==c.expected['count'] and len(values)<=8
                    c.expected['fifo']=values+[0]*(8-len(values))
                    c.note+='；r6按现行紧凑可见数组契约补齐尾部零，不引入$prefix判分扩展。'
            if decision=='adopt' and mode=='single' and signature(cases)[1:-1] in existing_single:
                decision='duplicate';reason='独立用例的输入、初态、拍数和断言与现行用例完全相同。'
            elif decision=='adopt' and mode!='single' and signature(cases) in old_sequence_signatures:
                decision='duplicate';reason='整段输入、初态、拍数和断言已存在，不重复增加分母。'
            row=dict(group=mode,first=cases[0].tc_id,count=len(cases),decision=decision,reason=reason)
            task_decisions.append(row)
            if decision=='adopt': admitted.extend(transformed)
        p.test_cases=old_cases+admitted
        assert len({c.tc_id for c in p.test_cases})==len(p.test_cases),p.pid+' duplicate case IDs'
        result=r5_judge.local_tests(source,p)
        assert result.compiles and result.all_tests_passed, (p.pid,result.failure_summary)
        sequences=traces(source,p)
        observer=observer_for(p.provenance.get('r9_spec_policy',{}).get('observer'))
        allowed={v.name.lower() for v in p.variables}
        if observer:allowed.update(observer({},None,True))
        known={re.sub(r'\s+','',s.ltl).lower() for s in p.specs if s.ltl}
        # Add supplemental formulas under new identifiers. Old SID meanings do
        # not silently change through an upstream spec_policy overlay.
        for spec in d['specs']:
            formula=re.sub(r'\bdt\b','scanSeconds',spec['ltl'],flags=re.I)
            if p.pid=='public-hard-04':
                formula=re.sub(r'\bcap\b','capacity',formula,flags=re.I)
                # The padded physical array has four cells even for logical
                # capacity two. Bound expressions in the generic contract must
                # therefore observe the fixed caller binding, not padded space.
                formula=re.sub(r'UPPER_BOUND\s*\(\s*buffer\s*,\s*1\s*\)\s*-\s*LOWER_BOUND\s*\(\s*buffer\s*,\s*1\s*\)\s*\+\s*1',
                               'capacity',formula,flags=re.I)
            key=re.sub(r'\s+','',formula).lower()
            if not formula or key in known:continue
            row=dict(pid=p.pid,source_sid=spec['sid'],formula=formula,text=spec['text'])
            if defer_all:row.update(status='deferred_contract',reason=reasons[p.pid])
            elif p.pid=='self-hard-04' and spec['sid']=='S9':
                row.update(status='deferred_contract',reason='该公式采用需求每次升档即重选备泵的另一契约。')
            else:
                row.update(formula_verdict(formula,sequences,allowed))
                if row['status']=='hold_on_test_traces':
                    s=Spec.from_dict({**spec,'sid':'N10-'+spec['sid'],'ltl':formula,
                        'text':'11.10补充：'+spec['text'],'verified_by':'test_trace_audit'})
                    p.specs.append(s);known.add(key)
            spec_decisions.append(row)
        p.provenance.update(review_revision='v1.3-review-r6',
            human_process_review=dict(status='pending',reviewer='刘晏铭',approved=False),
            review='11.10技术复核；上游自动验收及旧签署不作为本版工艺批准。')
        p.provenance['dataset_contract'].update(version='v1.3-review-r6',working_json=f'progress/v13_r6/datasets/{p.source}/{p.pid}.json',
            reference_source_sha256=sha(source.encode()),comparison_scope='r6 platform-adapted suite; r5 execution model; old results retained')
        write(ROOT/'datasets'/p.source/(p.pid+'.json'),p.to_dict())
        path=ROOT/'references'/(p.pid+'.reference.st');path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(source.encode())
        decisions.append(dict(pid=p.pid,original_cases=len(old_cases),incoming_cases=len(peer.test_cases),
            added_cases=len(admitted),current_cases=len(p.test_cases),groups=task_decisions,
            reference_changed=source!=previous.adapt(original)[1],
            requirements_changed=p.requirements!=previous.adapt(original)[0].requirements,
            source_reference_sha256=sha(source.encode()),supplemental_specs=len(p.specs)-len(original.specs)))
        print('built',p.pid,len(p.test_cases),'cases',len(p.specs),'specs',flush=True)
    assert sha(LEDGER.read_bytes())==before
    write(ROOT/'adoption.json',dict(date='2026-11-10',tasks=decisions,formulas=spec_decisions,
        old_cases_retained=583,model_calls=0,ledger_unchanged=True,
        note='New sequence groups may repeat earlier prefixes; row counts are assertions, not independent samples.'))
    write(ROOT/'config.offline.json',dict(live_enabled=False,models=[],budget_cny=None,
        campaign_root='progress/evidence/v13_r6_20261110',budget_ledger_path=str(LEDGER),
        data_version='v1.3-review-r6',primary_profile='codesys',mc_seconds=30))


def verify():
    mutable();v=revision();before=sha(LEDGER.read_bytes());rows=[];formula_rows=[]
    for p in v.problems():
        source=v.reference(p);result=r5_judge.local_tests(source,p)
        rows.append(dict(pid=p.pid,compiles=result.compiles,tests_passed=result.tests_passed,tests_total=result.tests_total,
            errors=result.compile_errors,failures=[c.to_dict() for c in result.cases if not c.passed]))
        assert result.compiles and result.all_tests_passed, p.pid
        seqs=traces(source,p);observer=observer_for(p.provenance.get('r9_spec_policy',{}).get('observer'))
        names={v.name.lower() for v in p.variables}
        if observer:names.update(observer({},None,True))
        for s in p.specs:
            if s.ltl:formula_rows.append(dict(pid=p.pid,sid=s.sid,**formula_verdict(s.ltl,seqs,names)))
    write(OUT/'references.json',rows);write(OUT/'formula_traces.json',formula_rows)
    # Explicitly separate legacy formula weaknesses from adopted supplements.
    assert all(r['status']=='hold_on_test_traces' for r in formula_rows if r['sid'].startswith('N10-'))
    suites=[]
    for pattern in ('test_v13_r6.py','test_v13_r5.py','test_v13_r4.py'):
        proc=subprocess.run([sys.executable,'-B','-X','utf8','-m','unittest','discover','-s','progress/tests','-p',pattern,'-q'],
            cwd=REPO,capture_output=True,text=True,encoding='utf-8',timeout=120)
        OUT.mkdir(parents=True,exist_ok=True);(OUT/(pattern+'.log')).write_bytes((proc.stdout+'\n'+proc.stderr).encode())
        assert proc.returncode==0,proc.stderr[-1600:]
        suites.append(dict(pattern=pattern,tests=int(re.search(r'Ran (\d+) tests?',proc.stderr)[1]),passed=True))
    properties=[s for p in v.problems() for s in p.specs]
    assert before==sha(LEDGER.read_bytes())
    write(OUT/'offline.json',dict(version=v.VERSION,execution_judge=v.JUDGE_VERSION,passed=True,
        cases=sum(r['tests_total'] for r in rows),cases_passed=sum(r['tests_passed'] for r in rows),
        total_properties=len(properties),runtime_ltl=sum(bool(s.ltl) for s in properties),
        suites=suites,formula_trace_statuses=dict(Counter(r['status'] for r in formula_rows)),
        native_results_reused=True,model_calls=0,ledger_unchanged=True,ledger_sha256=before,
        human_review='r6_pending',data_note='r6数据补强，沿用r5裁判；未重跑上游SMT，测试轨迹通过不等于穷尽证明。'))
    print('PASS references',sum(r['tests_total'] for r in rows),'formula statuses',Counter(r['status'] for r in formula_rows))


def native():
    mutable();v=revision();before=sha(LEDGER.read_bytes());rows=[]
    parent_path=REPO/'progress/evidence/v13_r4_20261108/native_references.json';prior=load(parent_path)
    olddata={p.pid:p for p in previous.problems()};cfg=load(v.ENGINE/'config.example.json')
    for cls in (CodesysBackend,OpenPLCBackend):
        backend=cls(cfg);identity=backend.identity()
        for p in v.problems():
            q,source,_=v.adapt(p,platform=backend.name)
            old=next(r for r in prior if r['pid']==p.pid and r['platform']==backend.name)
            if old['source_sha256']==sha(source.encode()) and old['platform_identity']==identity and old['status']=='passed':
                row=dict(pid=p.pid,platform=backend.name,status='passed',source_sha256=sha(source.encode()),
                    platform_identity=identity,reused=True,proof=parent_path.relative_to(REPO).as_posix(),proof_sha256=sha(parent_path.read_bytes()))
            else:
                report=backend.compile(source,q).to_dict()
                row=dict(report,pid=p.pid,platform=backend.name,source_sha256=sha(source.encode()),reused=False)
            rows.append(row);write(OUT/'native_references.json',rows)
            print('native',backend.name,p.pid,row['status'],'reused' if row['reused'] else 'fresh',flush=True)
            assert row['status']=='passed',(p.pid,backend.name,row)
    assert before==sha(LEDGER.read_bytes())
    report=load(OUT/'offline.json');report.update(native_reused=sum(r['reused'] for r in rows),native_fresh=sum(not r['reused'] for r in rows))
    write(OUT/'offline.json',report)


def rescore():
    mutable();v=revision();assert not SCORES.exists();before=sha(LEDGER.read_bytes())
    prior_path=REPO/'progress/evidence/v13_r5_rescore_20261108b/rescore.json';prior=load(prior_path)
    data={p.pid:p for p in v.problems()};groups={};details=[]
    for old in prior['details']:
        group,pid=old['group'],old['pid'];path=REPO/'progress/evidence/v13_rescore_20261108b/candidates'/group/(pid+'.st')
        raw=path.read_bytes() if path.exists() else b'';assert sha(raw)==old['code_sha256']
        sys.path.insert(0,str(ROOT))
        import r6_judge
        result=r6_judge.local_tests(raw.decode(),data[pid]) if raw else None
        unresolved=bool(result and result.evidence_metadata.get('classification') in ('unsupported_modeling','tool_error'))
        # r5 already resolved historical native-only boundaries. Reuse that
        # failure classification by the same source identity, not a new guess.
        prior_result=old.get('r5') or {}
        if unresolved and prior_result.get('evidence_metadata',{}).get('classification')=='candidate_native_error':
            result.compiles=False;result.mc_error='';result.evidence_metadata.update(classification='candidate_native_error',
                native_proof_reused_from=prior_path.relative_to(REPO).as_posix())
            result.platform_results=prior_result.get('platform_results',{});unresolved=False
        solved=bool(result and result.compiles and result.all_tests_passed)
        # A stronger suite cannot produce a new solved candidate. If it does,
        # require investigation rather than silently skipping native evidence.
        assert not solved or old['r5_solved'],(group,pid,'unexpected gain over retained old cases')
        row=groups.setdefault(group,dict(group=group,tasks=35,old_solved=0,new_solved=0,old_passed=0,new_passed=0,
            old_cases=583,new_cases=sum(len(p.test_cases) for p in data.values()),lost=[],gained=[],tool_errors=[]))
        row['old_solved']+=int(old['r5_solved']);row['new_solved']+=int(solved)
        row['old_passed']+=prior_result.get('tests_passed',0);row['new_passed']+=result.tests_passed if result else 0
        if old['r5_solved'] and not solved:row['lost'].append(pid)
        if unresolved:row['tool_errors'].append(pid)
        details.append(dict(group=group,pid=pid,code_sha256=old['code_sha256'],frozen_attempt_index=old['frozen_attempt_index'],
            r5_solved=old['r5_solved'],r6_solved=solved,r6=result.to_dict() if result else None))
    assert len(details)==140 and before==sha(LEDGER.read_bytes())
    write(SCORES/'rescore.json',dict(version=v.VERSION,baseline_label='r5固定答案（583用例）',current_label='r6相同答案',
        rows=list(groups.values()),details=details,fixed_candidates=True,model_calls=0,ledger_unchanged=True,
        baseline_score_sha256=sha(prior_path.read_bytes()),
        scope='same selected source bytes, stronger data suite; no model generation or candidate reselection; functional/native metric, not formal solved'))
    print(json.dumps(list(groups.values()),ensure_ascii=False))


def check():
    v=revision();v.verify_parent();m=load(ROOT/'snapshot_manifest.json')
    for name,expected in m['files'].items():assert sha((REPO/name).read_bytes())==expected,name
    print('PASS r6 and all frozen parent files')


def summarize():
    mutable();v=revision();offline=load(OUT/'offline.json');audit=load(ROOT/'adoption.json');scores=load(SCORES/'rescore.json')
    native_rows=load(OUT/'native_references.json')
    assert len(native_rows)==70 and all(r['status']=='passed' for r in native_rows)
    for row in native_rows:
        p=next(p for p in v.problems() if p.pid==row['pid'])
        assert row['source_sha256']==sha(v.reference(p).encode())
    offline.update(native_fresh=sum(not r['reused'] for r in native_rows),native_reused=sum(r['reused'] for r in native_rows))
    write(OUT/'offline.json',offline)
    labels={'custom_deepseek-v4pro':'自研 DeepSeek','codex_deepseek-v4pro':'Codex DeepSeek',
            'custom_minimax-m27':'自研 MiniMax','codex_minimax-m27':'Codex MiniMax'}
    lines=['# 11.10交接资料整理与采纳','',
        '本轮以冻结r5为基线，新建r6数据版本；执行裁判仍是r5。保留R8、R9、r1–r5及原选中答卷，不混入旧实验分母。',
        '', '## 收到的四份材料', '',
        '| 材料 | 内容与定位 | 本次处理 |','| --- | --- | --- |',
        '| genAI.rar | 11.8旧交接、547用例Word及旧复审页；Word文本和71张表已读取核对 | 归为历史材料；字面量/枚举、公开观察量、真实深度及单性质隔离等建议已在先前版本处理。未按旧建议直接改模型参数或缩窄正式输入域。 |',
        '| 题库修订_队友复核版.zip | 七题补丁和独立验算，预期由547扩到559 | 作为来源链，相关改动与当前r4逐项比较；不重复套旧补丁。 |',
        '| 复验包_20261108.zip | 七份原件和入口，可复现184/184；559是其全库报告数 | 在最终包保留的来源文件上复跑七题184/184，不把原包未交付28题的报告数写成实测。 |',
        '| STBench_F1.3_全库复核_最终工程.zip | 35题、863用例，报告320条有界公式及154个主要定向错解 | 功能863/863、快速完整性/来源/轨迹核验通过；本次未重跑SMT求解器和全部154个错解，不把这些主张移植为r6证明。 |',
        '', '四份原包保留于本机11.10意见目录；文件名、大小和SHA-256记录在ORIGIN_R5.json。采纳所用原始35份JSON、35份ST及说明单独保存在upstream/，不使用来件的付费运行器、专用证明器替换本地裁判。',
        '', '## 实施的调整', '',
        '1. 储罐：高/低危险条件优先于复位；危险消失后仍需新的复位沿。修复参考程序，并使高液位S1覆盖越限与复位同拍。',
        '2. 配方：收到合法装载沿而校验失败时，将loadedID归零；修正S1文字中“不得改变旧编号”与题面第5条的矛盾。',
        '3. 灌装：INT计数达到32767后保持，继续完成握手；复位后恢复计数。该边界在题面明示，避免违反原有计数不回退性质；仍待工艺复审。',
        '4. 保留旧583条断言，补入568条兼容断言，共1151条。独立重复用例和完全相同的序列组不重复增加分母；扩展序列可能包含旧前缀，1151是断言行数，不是1151份相互独立证据。',
        '5. 自建FIFO保留完整八格数组及尾部零断言，将来件$prefix按现行契约导出为明确数组；公共FIFO仍为固定容量2/4的DINT适配，公式中的数组长度绑定到逻辑capacity，不能读取补齐后的物理四格。',
        '6. 焊缝、板厚题面写明既有扫描计数口径；批次接口描述统一为拍数。没有把这些适配结果改称原始TIME或任意VARIANT通过率。',
        '', '## 未直接采纳的内容', '',
        '- 果酱泵25条新用例改成DebounceMs/CycleMs毫秒接口，与当前历史接口不同；留作独立契约版本。',
        '- 多泵来件seq整段12条含2→3需求升档重选备泵，与r4保持规则冲突，整段暂存；保留本地49/50/51边界并采纳LINT大工时组。',
        '- 闸门新34条改成下降遇障先停、不自动反向及双键组合沿复位，与原题“反向进入OPENING”等要求有冲突；原题面本身也有反向与停机时序歧义，等待明确，未用新参考解覆盖。',
        '- 新增候选公式125条在当前参考解的全部测试轨迹通过后纳入；20条因契约变更暂存，16条受当前LTL解析/嵌套历史算子支持限制暂存。每条公式的原文、判定和原因见adoption.json；不当作模型代码错误。',
        '- 当前共有345条性质，其中321条非空公式、24条仿真性质。测试轨迹检查319条成立、2条旧含未来算子的公式因轨迹不足未决（配方S4、灌装S2）；这不是321条形式证明。原模型检查输入域、深度、预算未自动更改。',
        '', '## 逐题采纳', '', '| 题号 | 原用例 | 来件用例 | 新增 | r6用例 | 参考解修改 |', '| --- | ---: | ---: | ---: | ---: | --- |']
    for row in audit['tasks']:
        lines.append(f'| {row["pid"]} | {row["original_cases"]} | {row["incoming_cases"]} | {row["added_cases"]} | {row["current_cases"]} | {"是" if row["reference_changed"] else "否"} |')
    lines+=['','## 同一批140份答卷的免费复验','','| 组别 | r5整题 /35 | r6整题 /35 | r6用例 /1151 | 新发现失败题 |','| --- | ---: | ---: | ---: | --- |']
    for row in scores['rows']:
        lines.append(f'| {labels[row["group"]]} | {row["old_solved"]} | {row["new_solved"]} | {row["new_passed"]} | {", ".join(row["lost"])} |')
    lines+=['','每份源代码SHA-256、原选中轮次保持不变，无新增整题通过，无工具未决；旧583条原断言仍通过的答案只因新增用例而退回。上述为原生/功能口径，不是规约全部通过。更强测试暴露漏检，不能解释为模型能力下降，也不替换R8正式结果。',
        '', '## 验收与下一步','',
        '1151/1151参考用例和64项检查通过；双平台参考解各35/35，6次新编译、64份按源码及当前平台身份复用。旧参考程序分别被新危险复位、无效配方、INT上限用例拒绝。模型请求0，账本38.409603元、438事件未变。',
        '', '先由刘晏铭确认泵、闸门与果酱泵的三个契约分歧，并复审三处参考修复；其余五道工业题及r4三题继续在同一来源链下复审。随后再决定单独升级LTL表达能力或毫秒契约。上游专用SMT、闭包、输入归约只能在检查适用范围并重跑后使用，不直接作为任意候选的通过依据。',
        '', '复审入口：[当前题面与用例](复审材料.html)，记录模板：[复审记录](复审记录.md)。可运行入口不接模型API，未启动新付费实验。','']
    (ROOT/'采纳与核验.md').write_bytes(('\n'.join(lines)).encode())
    # Case-level locations make the new losses reviewable without opening a JSON report.
    analysis=['# r6固定历史答案复验','','同一140份原选中源码，执行裁判仍为r5。583→1151条断言；旧分数保留，新增失败逐条列出。',
        '', '| 组别 | 题号 | 当前用例 | 首个新增失败 | 差异 |', '| --- | --- | ---: | --- | --- |']
    for d in scores['details']:
        if d['r5_solved'] and not d['r6_solved']:
            failure=next(c for c in d['r6']['cases'] if not c['passed'])
            assert failure['tc_id'].startswith('peer-')
            analysis.append(f'| {labels[d["group"]]} | {d["pid"]} | {d["r6"]["tests_passed"]}/{d["r6"]["tests_total"]} | {failure["tc_id"]} | {failure["message"].replace("|","/")} |')
    (SCORES/'重评分结果.md').write_bytes(('\n'.join(analysis)+'\n').encode())
    (ROOT/'README.md').write_bytes(('''# 11.10复核后的r6数据版本

以冻结r5为基线，整理四份交接包，采纳兼容断言并修正三处参考程序。数据为35题1151条用例，裁判仍沿用r5；旧版与原答卷不变。

[采纳、分歧及结果](采纳与核验.md) · [当前题面与用例](复审材料.html) · [逐条采纳记录](adoption.json) · [来源签名](ORIGIN_R5.json) · [验收](../evidence/v13_r6_20261110/acceptance.json)

参考用例1151/1151，64项回归通过，双平台参考解各35/35（6次新编译、64份复用）。保留原选中答卷后，整题由21/20/8/13变为18/16/7/10；变化来自测试补强，不能当作模型能力变化或改写R8正式结果。新增模型调用0。

当前345条性质含321条非空公式和24条仿真性质。319条通过测试轨迹检查，2条旧公式轨迹不足；未移植来件的320条有界证明。125条新公式在本地轨迹核验后采纳，另有36条因契约差异或表达能力不足暂存。

人工工艺复审仍待刘晏铭确认；果酱泵接口、多泵备选规则、闸门遇障时序三项分歧保留，未偷偷统一口径。完整记录见采纳说明。

```powershell
python -B -X utf8 progress/tools/v13_r6.py check
python -B -X utf8 -m unittest discover -s progress/tests -p test_v13_r6.py -q
```

本目录已导出平台适配契约，不可再次套用旧portability适配。正式入口为r6_judge.local_tests/evaluate，build/verify等写入命令仅供冻结前使用；冻结后须建新版本。不会启动模型请求。
''').encode())
    reviews=['# r6工艺复审记录模板','','版本：v1.3-review-r6；复审人：刘晏铭。当前全部待填写。请复制本模板后记录，新增签署另行归档，自动验收不能替代签署。',
        '', '## 必须明确的三个分歧','',
        '1. 果酱泵：是否采用新毫秒接口并与历史扫描版分开命名、分开评分？结论：待填写。',
        '2. 多泵：需求2→3、主泵不变时，备泵保持还是重选？本版保持，来件重选。结论：待填写。',
        '3. 闸门：下降遇障的本拍与下一拍各应输出什么？是否反向、持续障碍是否锁故障、双键如何复位？结论：待填写。',
        '', '## 逐题确认','']
    selected={'self-easy-02','self-medium-01','self-medium-04','self-hard-02','self-hard-04','public-medium-04',
        'self-hard-05','self-hard-06','self-hard-07','self-medium-05','self-medium-06'}
    for p in v.problems():
        if p.pid in selected:
            reviews += ['### '+p.pid,'','参考源码SHA-256：'+sha(v.reference(p).encode()),
                '', '结论（通过/需修改/无法判断）：待填写。','具体意见、依据及适用条件：待填写。','复审日期：待填写。','']
    (ROOT/'复审记录.md').write_bytes(('\n'.join(reviews)).encode())
    cards=[]
    for p in v.problems():
        variables=''.join(f'<tr><td>{escape(x.name)}</td><td>{escape(x.data_type)}</td><td>{escape(x.direction.value)}</td><td>{escape(x.description)}</td></tr>' for x in p.variables)
        cases=''.join('<tr>'+''.join('<td>'+escape(str(x))+'</td>' for x in (c.tc_id,c.mode or p.case_mode,c.cycles,
            json.dumps({**c.const_inputs,**c.inputs},ensure_ascii=False),json.dumps(c.init,ensure_ascii=False),json.dumps(c.expected,ensure_ascii=False),'完整' if c.expect_full else '部分',c.note))+'</tr>' for c in p.test_cases)
        specs=''.join(f'<li><b>{escape(s.sid)}</b> {escape(s.text)}<pre>{escape(s.ltl or "仿真性质")}</pre></li>' for s in p.specs)
        cards.append(f'<details class="task" data-title="{escape(p.pid+" "+p.title,quote=True)}"><summary>{escape(p.pid)} · {escape(p.title)} · {len(p.test_cases)}条</summary><p>人工结论：待刘晏铭填写；参考源码SHA-256：<code>{sha(v.reference(p).encode())}</code></p><pre>{escape(p.requirements)}</pre><div class="scroll"><table><tr><th>变量</th><th>类型</th><th>方向</th><th>说明</th></tr>{variables}</table></div><h3>性质</h3><ul>{specs}</ul><h3>用例</h3><p>相同sequence组连续；不同组新实例；single每条独立。输入包含本行常量，未写BOOL按FALSE处理；初态在本行扫描前设置。cycles为本行实际扫描次数。断言范围列注明是否强制完整输出。</p><div class="scroll"><table><tr><th>编号</th><th>组</th><th>拍数</th><th>有效输入</th><th>初态</th><th>预期</th><th>断言范围</th><th>说明</th></tr>{cases}</table></div></details>')
    table=''.join(f'<tr><td>{escape(labels[r["group"]])}</td><td>{r["old_solved"]}/35</td><td>{r["new_solved"]}/35</td><td>{r["new_passed"]}/1151</td></tr>' for r in scores['rows'])
    html='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>11.10项目状态与复审材料</title><style>
body{margin:0;background:#f4f6fa;color:#243249;font:16px/1.7 system-ui,"Microsoft YaHei",sans-serif}main{max-width:1180px;margin:auto;padding:28px 20px}section,details{background:white;border:1px solid #dde3ec;border-radius:10px;padding:20px;margin:18px 0}summary{cursor:pointer;font-weight:650}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f7f8fb;padding:12px;font-size:13px}code{overflow-wrap:anywhere}.scroll{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:13px}th,td{border:1px solid #dde3ec;padding:9px;text-align:left;vertical-align:top;min-width:70px;overflow-wrap:anywhere}th{background:#edf2f8}a{color:#175eac}input{font:inherit;padding:10px;border:1px solid #b9c7d8;border-radius:6px;width:min(90%,480px)}.pending{color:#855909}
</style><main><h1>11.10项目状态与复审材料</h1><p>r6数据 · 沿用r5裁判 · 当前没有付费实验运行</p>
<section><h2>已完成</h2><p><b>1151/1151</b> 参考断言通过；保留旧583条，补入568条。64项回归通过，双平台参考解各35/35（6次新编译、64份复用）。新增模型费用0元，累计38.409603/75元。</p><p>已修正危险液位复位、配方无效后编号清零、灌装INT上限保持。新增断言含重复前缀，断言数不等于独立证据数。</p></section>
<section><h2>同一批历史答卷</h2><div class="scroll"><table><tr><th>组别</th><th>r5（583用例）</th><th>r6（1151用例）</th><th>r6通过断言</th></tr>'''+table+'''</table></div><p>固定140份源码与原选中轮次，新增用例揭示旧漏检；不代表模型能力下降，不替换R8正式结果。</p></section>
<section><h2>仍需明确</h2><p class="pending">果酱泵是否另立毫秒接口；需求2→3时备泵是否重选；闸门遇障是否反向及每拍动作。这三处尚未统一，冲突材料留存。</p><p>刘晏铭需要确认工艺动作及三处参考修复。<a href="复审记录.md">打开复审记录模板</a> · <a href="采纳与核验.md">查看四包整理与采纳说明</a></p><p>321条非空公式中319条通过测试轨迹检查，2条旧公式轨迹不足。未重跑上游SMT、未将其证明当作任意候选的证明。另有24条仿真性质；36条来件公式暂存。</p></section>
<h2>当前35题</h2><p>以下为平台适配后的实际评分契约。原始TIME、VARIANT接口差异按来源保留，不能把本版成绩解释为未经适配的上游成绩。</p><input id="search" aria-label="筛选题目" placeholder="输入题号或名称筛选">'''+''.join(cards)+'''</main><script>document.getElementById('search').addEventListener('input',function(){const q=this.value.toLowerCase();document.querySelectorAll('.task').forEach(x=>x.hidden=!x.dataset.title.toLowerCase().includes(q));});</script></html>'''
    (ROOT/'复审材料.html').write_bytes(html.encode())
    print('PASS reports and current review catalogue')


def freeze():
    mutable();v=revision();v.verify_parent();report=load(OUT/'offline.json');scores=load(SCORES/'rescore.json')
    assert report['cases_passed']==report['cases'] and len(load(OUT/'native_references.json'))==70
    assert sha(LEDGER.read_bytes())==report['ledger_sha256']
    write(OUT/'acceptance.json',dict(version=v.VERSION,technical_passed=True,model_calls=0,
        ledger_unchanged=True,spent_cny=load(LEDGER)['spent_cny'],ledger_events=len(load(LEDGER)['events']),
        cases=report['cases'],cases_passed=report['cases_passed'],tests=sum(s['tests'] for s in report['suites']),
        native_fresh=report['native_fresh'],native_reused=report['native_reused'],
        fixed_candidates=len(scores['details']),human_review='r6_pending',formal_scope='test trace audit only; no upstream SMT transfer'))
    paths=[p for base in (ROOT,OUT,SCORES) for p in base.rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.name!='status_viewer.json']
    paths += [Path(__file__),REPO/'progress/tests/test_v13_r6.py']
    write(ROOT/'snapshot_manifest.json',dict(version=v.VERSION,files={p.relative_to(REPO).as_posix():sha(p.read_bytes()) for p in sorted(paths)}))
    print('PASS frozen r6')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['build','verify','native','rescore','summarize','freeze','check'])
    parser.add_argument('--incoming',type=Path)
    args=parser.parse_args()
    if args.command=='build':
        if not args.incoming:parser.error('build requires --incoming')
        build(args.incoming)
    else:globals()[args.command]()

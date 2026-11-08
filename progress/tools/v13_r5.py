"""Free r5 verification and fixed-code replay over immutable r4 data."""
import argparse
import copy
import json
from pathlib import Path
import re
import subprocess
import sys

REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO/'progress/v13_r5'))
import r5_revision as v
import r5_judge as judge
from conversions import runtime
from stbench.platforms import CodesysBackend,OpenPLCBackend
from stbench.schema import Problem
OUT=REPO/'progress/evidence/v13_r5_20261108'
SCORES=REPO/'progress/evidence/v13_r5_rescore_20261108b'
PILOT_REPLAY=OUT/'pilot_replay_b.json'
PILOT=REPO/'progress/evidence/r4_check_order_20261108'
LEDGER=Path('E:/PLC_Dev/evidence/dmxapi_budget_75.json')


def load(p):return json.loads(p.read_text('utf-8'))
def write(p,d):
    p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((json.dumps(d,ensure_ascii=False,indent=2)+'\n').encode())
def mutable():assert not (v.ROOT/'snapshot_manifest.json').exists(),'r5 frozen; use check or a new version'


def verify():
    mutable();before=v.digest(LEDGER.read_bytes());rows=[];suites=[]
    for p in v.problems():
        q,code,_=v.adapt(p);r=judge.local_tests(code,q)
        rows.append(dict(pid=p.pid,compiles=r.compiles,tests_passed=r.tests_passed,tests_total=r.tests_total,
            errors=r.compile_errors,failures=[c.to_dict() for c in r.cases if not c.passed]))
    write(OUT/'references.json',rows)
    assert len(rows)==35 and sum(r['tests_passed'] for r in rows)==583
    assert all(r['compiles'] and r['tests_passed']==r['tests_total'] for r in rows)
    OUT.mkdir(parents=True,exist_ok=True)
    for pattern in ('test_v13_r5.py','test_v13_r4.py'):
        proc=subprocess.run([sys.executable,'-B','-X','utf8','-m','unittest','discover','-s','progress/tests','-p',pattern,'-q'],
            cwd=REPO,capture_output=True,text=True,encoding='utf-8',timeout=120)
        (OUT/(pattern+'.log')).write_bytes((proc.stdout+'\n'+proc.stderr).encode())
        assert proc.returncode==0,proc.stderr[-1800:]
        suites.append(dict(pattern=pattern,tests=int(re.search(r'Ran (\d+) tests?',proc.stderr)[1]),passed=True))
    old_path=REPO/'progress/evidence/v13_r4_20261108/native_references.json'
    prior=load(old_path);native=[];cfg=load(v.ENGINE/'config.example.json')
    for cls in (CodesysBackend,OpenPLCBackend):
        backend=cls(cfg);identity=backend.identity()
        for p in v.problems():
            _,code,_=v.adapt(p,platform=backend.name)
            row=next(r for r in prior if r['pid']==p.pid and r['platform']==backend.name)
            assert row['source_sha256']==v.digest(code.encode()) and row['platform_identity']==identity and row['status']=='passed'
            native.append(dict(pid=p.pid,platform=backend.name,status='passed',reference_source_sha256=v.digest(code.encode()),
                proof=old_path.relative_to(REPO).as_posix(),proof_sha256=v.digest(old_path.read_bytes())))
    assert v.digest(LEDGER.read_bytes())==before
    grouped=[dict(platform=name,entries=[r for r in native if r['platform']==name],
        source=old_path.relative_to(REPO).as_posix(),source_sha256=v.digest(old_path.read_bytes())) for name in ('codesys','openplc')]
    properties=[s for p in v.problems() for s in v.adapt(p)[0].specs]
    write(OUT/'offline.json',dict(version=v.VERSION,data_version=v.DATA_VERSION,passed=True,cases=583,cases_passed=583,
        suites=suites,rows=rows,native_reference_passes=70,native_results_reused=True,native_evidence=grouped,native_probes_count=12,
        total_properties=len(properties),raw_ltl=sum(bool(s.ltl) for p in v.problems() for s in p.specs),
        runtime_ltl=sum(bool(s.ltl) for s in properties),
        model_calls=0,ledger_unchanged=True,ledger_sha256=before,human_review='r4_pending'))
    print('PASS verify 583/583;',sum(s['tests'] for s in suites),'tests; 70 native reference proofs revalidated',flush=True)


def fixture(name,source_type='DINT',output_type='INT',body='outputValue:=TO_INT(inputValue);'):
    p=Problem.from_dict(dict(pid='r5-'+name,source='selfmade',difficulty='easy',title=name,requirements='language control',
        variables=[dict(name='inputValue',data_type=source_type,direction='input'),dict(name='outputValue',data_type=output_type,direction='output')]))
    code=f'FUNCTION_BLOCK FB VAR_INPUT inputValue:{source_type}; END_VAR VAR_OUTPUT outputValue:{output_type}; END_VAR {body} END_FUNCTION_BLOCK'
    return p,code


def native():
    mutable();before=v.digest(LEDGER.read_bytes());cfg=load(v.ENGINE/'config.example.json');rows=[]
    previous=load(OUT/'native_probes.json').get('rows',[]) if (OUT/'native_probes.json').exists() else []
    specs=[('integer',*fixture('integer'),True),
        ('bool',*fixture('bool','INT','BOOL','outputValue:=TO_BOOL(inputValue);'),True),
        ('return',*fixture('return',body='outputValue:=TO_INT(inputValue); IF inputValue>0 THEN RETURN; END_IF; outputValue:=1;'),True),
        ('real_unmodeled',*fixture('real','REAL'),True),
        ('arity',*fixture('arity',body='outputValue:=TO_INT(inputValue,2);'),False),
        ('unknown',*fixture('unknown',body='outputValue:=TO_INVENTED(inputValue);'),False)]
    for cls in (CodesysBackend,OpenPLCBackend):
        backend=cls(cfg)
        for name,p,code,expected in specs:
            cached=next((r for r in previous if r['fixture']==name and r['platform']==backend.name
                and r['source_sha256']==v.digest(code.encode()) and r['platform_identity']==backend.identity()),None)
            report={key:value for key,value in cached.items() if key not in ('fixture','source','source_sha256','expected_status')} if cached else backend.compile(code,p).to_dict()
            row=dict(report)
            row.update(fixture=name,platform=backend.name,source=code,source_sha256=v.digest(code.encode()),
                expected_status='passed' if expected else 'failed')
            rows.append(row)
            write(OUT/'native_probes.json',dict(complete=False,rows=rows))
            if not (name=='unknown' and backend.name=='openplc'):
                assert report['status']==('passed' if expected else 'failed'),(name,backend.name,report['status'])
            print('native',backend.name,name,report['status'],flush=True)
    assert v.digest(LEDGER.read_bytes())==before
    deviations=[dict(fixture=r['fixture'],platform=r['platform'],expected=r['expected_status'],observed=r['status'])
        for r in rows if r['expected_status']!=r['status']]
    write(OUT/'native_probes.json',dict(complete=True,required_controls_passed=True,rows=rows,model_calls=0,
        all_initial_expectations_met=not deviations,deviations=deviations,
        initial_observations_sha256=v.digest((OUT/'native_probes_initial.json').read_bytes()) if (OUT/'native_probes_initial.json').exists() else None,
        scope='compile/package observations, not runtime proof; OpenPLC accepted unknown-function control, so local unknown-function rejection remains mandatory'))


def pilot():
    mutable();assert not PILOT_REPLAY.exists(),'Use a new replay filename'
    before=v.digest(LEDGER.read_bytes());data={p.pid:p for p in v.problems()};rows=[];details=[]
    plan=load(PILOT/'study_plan.json');old_summary=load(PILOT/'analysis.json')
    for job in plan['jobs']:
        path=PILOT/'jobs'/job['condition']/(job['pid']+'.json');original=load(path)
        q,_,_=v.adapt(data[job['pid']]);attempts=[]
        for a in original['attempts']:
            source=a['code'];sha=v.digest(source.encode());assert not source or sha==a['code_hash']
            result=judge.local_tests(source,q) if source else None
            attempts.append(dict(idx=a['idx'],code_sha256=sha,source_present=bool(source),
                r4_solved=a['solved'],r5_local_solved=bool(result and result.compiles and result.all_tests_passed),
                r4_tests_passed=a['tests_passed'],r5=result.to_dict() if result else None))
        selected=next((a for a in attempts if a['idx']==original['best_attempt']),None)
        details.append(dict(job_id=job['job_id'],condition=job['condition'],pid=job['pid'],
            original_record_sha256=v.digest(path.read_bytes()),frozen_best_attempt=original['best_attempt'],
            r4_solved=original['solved'],r5_frozen_selected_solved=bool(selected and selected['r5_local_solved']),
            any_saved_attempt_passes=any(a['r5_local_solved'] for a in attempts),attempts=attempts))
    for old in old_summary['rows']:
        arm=[d for d in details if d['condition']==old['condition']]
        rows.append(dict(condition=old['condition'],n=2,r4_solved=old['solved'],
            r5_frozen_selected_solved=sum(d['r5_frozen_selected_solved'] for d in arm),
            any_saved_attempt_passes=sum(d['any_saved_attempt_passes'] for d in arm)))
    entry=next(d for d in details if d['job_id']=='codex_always_mc/public-hard-04')
    path=PILOT/'jobs/codex_always_mc/public-hard-04.json';original=load(path)['attempts'][1]
    q,_,_=v.adapt(data['public-hard-04']);source=original['code']
    conversion_only=runtime('codesys',False).evaluation.local_tests(source,q)
    complete=judge.evaluate(source,q,timeout_s=40)
    assert complete.compiles and complete.all_tests_passed
    assert v.digest(LEDGER.read_bytes())==before
    write(PILOT_REPLAY,dict(version=v.VERSION,data_version=v.DATA_VERSION,rows=rows,details=details,
        actual_submissions=sum(len(d['attempts']) for d in details),original_best_indices_preserved=True,model_calls=0,
        diagnostic_pool_is_not_new_framework_score=True,
        ablation=dict(job_id=entry['job_id'],attempt=1,candidate_sha256=original['code_hash'],
            r4=original['judge'],conversion_only=conversion_only.to_dict(),r5=complete.to_dict()),ledger_unchanged=True))
    print('PASS pilot fixed selections and all saved attempts',json.dumps(rows,ensure_ascii=False),flush=True)


def rescore():
    mutable();assert not SCORES.exists(),'Use a new score directory'
    before=v.digest(LEDGER.read_bytes());prior_path=REPO/'progress/evidence/v13_r4_rescore_20261108b/rescore.json'
    prior=load(prior_path);data={p.pid:p for p in v.problems()};details=[];groups={}
    backend=CodesysBackend(load(v.ENGINE/'config.example.json'));identity=backend.identity()
    earlier_path=REPO/'progress/evidence/v13_r5_rescore_20261108/rescore.json'
    earlier={(d['group'],d['pid']):d for d in load(earlier_path)['details']} if earlier_path.exists() else {}
    for old in prior['details']:
        group,pid=old['group'],old['pid'];path=REPO/'progress/evidence/v13_rescore_20261108b/candidates'/group/(pid+'.st')
        raw=path.read_bytes() if path.exists() else b'';assert v.digest(raw)==old['code_sha256']
        q,_,_=v.adapt(data[pid]);result=None;error='';boundary=None
        try:
            result=judge.local_tests(raw.decode(),q) if raw else None
            if result and result.evidence_metadata.get('classification')=='unsupported_modeling':
                prior_native=(old.get('r4') or {}).get('platform_results',{}).get('codesys')
                if prior_native and prior_native.get('platform_identity')==identity and prior_native['status']=='failed':
                    result.platform_results={'codesys':prior_native};result.compiles=False;result.mc_error=''
                    result.evidence_metadata.update(classification='candidate_native_error',
                        native_proof_reused_from=prior_path.relative_to(REPO).as_posix(),native_proof_candidate_sha256=old['code_sha256'])
                else:result=judge.strings.resolve_native(result,raw.decode(),q,(backend,),timeout_s=90)
            solved=bool(result and result.compiles and result.all_tests_passed)
            if solved and not old['r4_solved']:
                cached=earlier.get((group,pid),{})
                boundary=cached.get('new_native_boundary')
                if not (cached.get('code_sha256')==old['code_sha256'] and boundary and
                        boundary.get('platform_identity')==identity and boundary['status']=='passed'):
                    boundary=backend.compile(raw.decode(),q).to_dict()
                else:result.evidence_metadata['native_boundary_reused_from']=earlier_path.relative_to(REPO).as_posix()
                result.platform_results['codesys']=boundary
                if boundary['status']!='passed':solved=False
        except Exception as exc:error=type(exc).__name__+': '+str(exc);solved=False
        g=groups.setdefault(group,dict(group=group,tasks=35,old_cases=583,new_cases=583,old_solved=0,new_solved=0,
            old_passed=0,new_passed=0,lost=[],gained=[],tool_errors=[]))
        g['old_solved']+=int(old['r4_solved']);g['new_solved']+=int(solved)
        g['old_passed']+=(old.get('r4') or {}).get('tests_passed',0);g['new_passed']+=result.tests_passed if result else 0
        if old['r4_solved'] and not solved:g['lost'].append(pid)
        if solved and not old['r4_solved']:g['gained'].append(pid)
        if error or (result and result.evidence_metadata.get('classification') in ('unsupported_modeling','tool_error')):
            g['tool_errors'].append(pid)
        details.append(dict(group=group,pid=pid,code_sha256=old['code_sha256'],frozen_attempt_index=old['frozen_attempt_index'],
            r4_solved=old['r4_solved'],r5_solved=solved,r5=result.to_dict() if result else None,error=error,new_native_boundary=boundary))
    assert len(details)==140 and v.digest(LEDGER.read_bytes())==before
    write(SCORES/'rescore.json',dict(version=v.VERSION,data_version=v.DATA_VERSION,baseline_label='r4原选中答案',current_label='r5同一答案',
        rows=list(groups.values()),details=details,fixed_candidates=True,model_calls=0,ledger_unchanged=True,
        baseline_score_sha256=v.digest(prior_path.read_bytes()),
        scope='same 140 originally selected R8 candidates, same r4 data; only judge changes; no candidate reselection or model generation'))
    lines=['# r5固定历史答案免费复验','','两侧都使用r4数据35题583用例，保留140个原选中轮次和源码字节。这里只修订裁判，不声称模型生成能力提升。','',
        '| 组别 | r4整题 | r5整题 | r4用例 | r5用例 | 新通过 | 退回 | 未决 |','| --- | ---: | ---: | ---: | ---: | --- | --- | --- |']
    for g in groups.values():
        lines.append(f'| {g["group"]} | {g["old_solved"]}/35 | {g["new_solved"]}/35 | {g["old_passed"]}/583 | {g["new_passed"]}/583 | {", ".join(g["gained"]) or "无"} | {", ".join(g["lost"]) or "无"} | {", ".join(g["tool_errors"]) or "无"} |')
    (SCORES/'重评分结果.md').write_bytes(('\n'.join(lines)+'\n').encode())
    print(json.dumps(list(groups.values()),ensure_ascii=False),flush=True)


def diagnostics():
    mutable();target=OUT/'counterexample_replay_b.json';assert not target.exists()
    saved=load(PILOT_REPLAY);example=saved['ablation']
    assert example['r5']['tests_passed']==27
    violation=next(s for s in example['r5']['model_check']['violations'] if s['id']=='S4')
    candidate=load(PILOT/'jobs/codex_always_mc/public-hard-04.json')['attempts'][1]['code']
    assert v.digest(candidate.encode())==example['candidate_sha256']
    p=next(p for p in v.problems() if p.pid=='public-hard-04');q,reference,_=v.adapt(p)
    from conversions import checked
    from stbench.st.frontend import compile_st
    from stbench.ltl import evaluate
    engine=runtime('codesys');formula=next(s.ltl for s in q.specs if s.sid=='S4')
    rows=[]
    for name,source in [('original_candidate',candidate),('reference',reference)]:
        parsed,_=checked(compile_st(source));assert parsed.ok
        interp=engine.Interpreter(parsed.pou,parsed.structs);initial=copy.deepcopy(interp.mem)
        snapshots=[];scans=[]
        for index,step in enumerate(violation['trace'],1):
            inputs={variable.name:step[variable.name.lower()] for variable in q.inputs}
            for key,value in inputs.items():interp.set_var(key,value)
            interp.scan();snapshots.append(copy.deepcopy(interp.mem))
            scans.append(dict(scan=index,inputs=inputs,status=interp.get_var('status'),
                elementCount=interp.get_var('elementCount')))
        verdict=evaluate(formula,snapshots,engine.modelcheck._atom_evaluator(interp.types,parsed.structs),init_snapshot=initial)
        rows.append(dict(program=name,scans=scans,holds=verdict.holds,inconclusive=verdict.inconclusive,counterexample_at=verdict.counterexample_at))
    assert not rows[0]['holds'] and rows[0]['counterexample_at']==5 and rows[1]['holds']
    write(target,dict(version=v.VERSION,candidate_sha256=example['candidate_sha256'],formula_id='S4',formula=formula,
        scope='same five input scans replayed in r5; separate diagnostic, no dataset or candidate edits',model_calls=0,results=rows))
    print('PASS five-scan S4 counterexample: candidate violates, reference holds',flush=True)


def summarize():
    mutable();scores=load(SCORES/'rescore.json');pilot_result=load(PILOT_REPLAY);details=[]
    data={p.pid:p for p in v.problems()}
    for d in scores['details']:
        if d['r4_solved']==d['r5_solved']:continue
        path=REPO/'progress/evidence/v13_rescore_20261108b/candidates'/d['group']/(d['pid']+'.st')
        code=path.read_text('utf-8');assert v.digest(code.encode())==d['code_sha256']
        q,_,_=v.adapt(data[d['pid']])
        legacy=runtime('codesys',False).evaluation.local_tests(code,q)
        details.append(dict(group=d['group'],pid=d['pid'],code_sha256=d['code_sha256'],
            conversion_only_passed=legacy.tests_passed,r5_passed=d['r5']['tests_passed'],total=d['r5']['tests_total'],
            current_native_status=d['new_native_boundary']['status']))
    write(OUT/'historical_return_ablations.json',dict(model_calls=0,source_unchanged=True,results=details))
    prior=load(REPO/'progress/evidence/v13_r4_rescore_20261108b/rescore.json')
    lookup={(d['group'],d['pid']):d for d in prior['details']};case_changes=[]
    for d in scores['details']:
        old=(lookup[(d['group'],d['pid'])].get('r4') or {}).get('tests_passed',0)
        new=(d.get('r5') or {}).get('tests_passed',0)
        if old!=new:case_changes.append(dict(group=d['group'],pid=d['pid'],old_passed=old,new_passed=new,total=d['r5']['tests_total']))
    report=dict(version=v.VERSION,data_version=v.DATA_VERSION,fixed_140_rows=scores['rows'],case_changes=case_changes,
        pilot_rows=pilot_result['rows'],fifo_functional_passed=27,fifo_functional_total=27,fifo_ltl_violated=['S4'],
        model_calls=0,ledger_unchanged=True,
        interpretation='Judge correction only. Original selected indices stay fixed; other saved submissions are separate diagnostics. Test success does not imply all properties hold.')
    write(OUT/'report.json',report)
    lines=['# r5裁判修复与免费复验结论','','数据仍为冻结的r4，35题583用例；本轮没有模型请求。旧数据、选中答案、实验结果及费用账本均保留。','',
        '本轮修复通用整数转换的类型推断与直接执行，以及RETURN结束本次扫描的控制流。候选源码不改写；新检查器、解释器及模型检查在私有模块中绑定，旧模块保持。','',
        '## 原FIFO答卷的归因链','',
        '| 检查方式 | 原始代码的结果 |','| --- | --- |',
        '| r4 | TO_INT被报未知函数，功能未决 |','| 只加入通用转换，保留旧RETURN行为 | 23/27用例通过，复位后仍执行后续语句 |',
        '| r5转换与RETURN都修复 | 27/27用例通过；形式检查发现S4反例 |','',
        '同一条五拍轨迹下，容量为2，满队时入队与出队同时出现上升沿，候选最终elementCount=1但status=32770；S4要求该状态码意味着队列仍满。参考程序在同轨迹末保持elementCount=2、status=32770，满足S4。反例单独保存，未修改原27条测试或候选。','',
        '## 固定140份历史答案','',
        '| 组别 | r4整题 | r5整题 | r4用例 | r5用例 |','| --- | ---: | ---: | ---: | ---: |']
    for r in scores['rows']:lines.append(f'| {r["group"]} | {r["old_solved"]}/35 | {r["new_solved"]}/35 | {r["old_passed"]}/583 | {r["new_passed"]}/583 |')
    lines += ['','两份MiniMax/public-easy-03答案恢复通过：转换-only对照分别为7/8、6/8，r5均为8/8，说明整题变化来自RETURN修复。两份源码均经CODESYS接受，原选中轮次保持不变。这是裁判纠错，不是新模型能力提升。另有未整题通过的答卷增加用例通过数，全部差异如下。','',
        '| 组别 | 题号 | r4用例 | r5用例 |','| --- | --- | ---: | ---: |']
    for r in case_changes:lines.append(f'| {r["group"]} | {r["pid"]} | {r["old_passed"]}/{r["total"]} | {r["new_passed"]}/{r["total"]} |')
    lines += ['',
        '## 保留小试验原选择','',
        '原8题次选中轮次的复评分不变：自研持续0/2、Codex后置1/2、自研后置1/2、Codex持续0/2。Codex持续/FIFO原先选中第0轮；第1轮是这次查明27/27通过的答卷。后者仅作为已保存候选集的补充诊断，不替换原选中轮次，也未借此重选更好答案。其S4仍违反，不能补成完整规约成功。','',
        '## 验收与边界','',
        '583/583参考用例、30项r5检查和19项r4回归通过；70份参考原生编译证据按相同源码与当前编译器身份复用。12项原生对照包括正常整数/布尔转换、RETURN、浮点转换接受情况以及参数/未知函数控制。',
        'CODESYS拒绝未知函数；OpenPLC对该未知函数样例仍打包接受。原假设和原观察保留，不将打包通过视为存在有效执行语义。本地未知函数仍拒绝。浮点、字符串、日期时间、枚举、超出目标范围的转换和条件式RETURN均保留未建模；已确认的反例不会被后续未建模路径抹掉，单条性质异常不清空其他性质。','',
        '本次模型费用0，账本仍38.409603元、438事件。人工工艺结论仍待刘晏铭确认。本版没有付费运行入口；下一步可先用冻结的生成记录分析声明缺失与扫描末输出问题，再另立单变量生成策略诊断。']
    (OUT/'结果说明.md').write_bytes(('\n'.join(lines)+'\n').encode())
    print('PASS r5 report and attribution checks',flush=True)


def freeze():
    mutable();v.verify_parent();proof=load(OUT/'offline.json');scores=load(SCORES/'rescore.json');pilot_result=load(PILOT_REPLAY)
    native=load(OUT/'native_probes.json')
    assert proof['passed'] and native['complete'] and native['required_controls_passed'] and len(scores['details'])==140
    assert pilot_result['original_best_indices_preserved'] and v.digest(LEDGER.read_bytes())==proof['ledger_sha256']
    assert (OUT/'report.json').exists() and (OUT/'counterexample_replay_b.json').exists()
    acceptance=dict(version=v.VERSION,data_version=v.DATA_VERSION,technical_passed=True,cases=583,cases_passed=583,
        tests=sum(s['tests'] for s in proof['suites']),suites=proof['suites'],native_reused=70,native_probes=12,
        fixed_historical_candidates=140,pilot_original_jobs=8,pilot_saved_submissions=pilot_result['actual_submissions'],
        model_calls=0,ledger_unchanged=True,ledger_sha256=proof['ledger_sha256'],spent_cny=load(LEDGER)['spent_cny'],
        ledger_events=len(load(LEDGER)['events']),human_review='r4_pending',original_versions_unchanged=True)
    write(OUT/'acceptance.json',acceptance)
    files=[p for p in v.ROOT.rglob('*') if p.is_file() and '__pycache__' not in p.parts]
    files += [Path(__file__),REPO/'progress/tests/test_v13_r5.py']
    write(v.ROOT/'snapshot_manifest.json',dict(version=v.VERSION,
        files={p.relative_to(REPO).as_posix():v.digest(p.read_bytes()) for p in sorted(files)},
        evidence_sha256={p.relative_to(REPO).as_posix():v.digest(p.read_bytes()) for p in sorted(OUT.rglob('*')) if p.is_file() and p.name!='status_viewer.json'},
        rescore_sha256=v.digest((SCORES/'rescore.json').read_bytes()),human_review='r4_pending',
        additional_proof_sha256={p.relative_to(REPO).as_posix():v.digest(p.read_bytes())
            for p in [SCORES/'重评分结果.md',*(REPO/'progress/evidence/v13_r5_rescore_20261108').glob('*')] if p.is_file()}))
    print('PASS frozen r5',flush=True)


def check():
    v.verify_parent();m=load(v.ROOT/'snapshot_manifest.json')
    for name,expected in {**m['files'],**m['evidence_sha256'],**m.get('additional_proof_sha256',{})}.items():assert v.digest((REPO/name).read_bytes())==expected,name
    assert v.digest((SCORES/'rescore.json').read_bytes())==m['rescore_sha256']
    print('PASS r5, r4 and original pilot frozen hashes',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('command',choices=['verify','native','pilot','rescore','diagnostics','summarize','freeze','check'])
    globals()[parser.parse_args().command]()

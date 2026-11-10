"""Free formula-layer acceptance, fixed-answer checks and failure triage."""
import argparse
from collections import Counter
import copy
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO/'progress/v13_r7'))
import r7_revision as v
import r7_ltl as ltl
import r7_judge as judge
from stbench.platforms import CodesysBackend,OpenPLCBackend
from stbench.st.interp import ArrayValue

OUT=REPO/'progress/evidence/v13_r7_20261110'
LEDGER=Path('E:/PLC_Dev/evidence/dmxapi_budget_75.json')
spec=importlib.util.spec_from_file_location('r7_frozen_trace_replay',REPO/'progress/tools/v13_r6.py')
tracer=importlib.util.module_from_spec(spec);spec.loader.exec_module(tracer)


def load(p):return json.loads(p.read_text('utf-8'))
def write(p,d):
    p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((json.dumps(d,ensure_ascii=False,indent=2)+'\n').encode())
def mutable():assert not (v.ROOT/'snapshot_manifest.json').exists(),'r7 frozen; use a new version'


def verdict(formula,sequences):
    uncertain=None
    for seq in sequences:
        try:
            result=ltl.evaluate(formula,seq['frames'],seq['atom'],init_snapshot=seq['initial'])
            if result.inconclusive:uncertain=uncertain or dict(status='inconclusive',group=seq['group'],reason=result.reason)
            elif not result.holds:
                return dict(status='violated',group=seq['group'],scan=result.counterexample_at,
                    case=seq['ids'][result.counterexample_at-1])
        except Exception as exc:return dict(status='error',reason=type(exc).__name__+': '+str(exc))
    return uncertain or dict(status='hold_on_test_traces')


def verify():
    mutable();v.verify_parent();before=v.digest(LEDGER.read_bytes());rows=[];formulas=[];controls=[]
    overlay=load(v.ROOT/'spec_overlay.json')
    for p in v.problems():
        source=v.reference(p);r=judge.local_tests(source,p)
        assert r.compiles and r.all_tests_passed,p.pid
        rows.append(dict(pid=p.pid,tests_passed=r.tests_passed,tests_total=r.tests_total,source_sha256=v.digest(source.encode())))
        seqs=tracer.traces(source,p)
        for s in p.specs:
            if s.ltl:formulas.append(dict(pid=p.pid,sid=s.sid,**verdict(s.ltl,seqs)))
        for item in overlay:
            if item['pid']!=p.pid:continue
            found=None
            # Perturb copied output snapshots only. These are sensitivity
            # controls, not new functional cases or claims of ST equivalence.
            for seq in seqs:
                if found:break
                for index,frame in enumerate(seq['frames']):
                    if found:break
                    for variable in p.outputs:
                        key=variable.name.lower();old=frame.get(key)
                        if isinstance(old,bool):new=not old
                        elif isinstance(old,int):new=old+1
                        elif isinstance(old,float):new=old+1.0
                        elif isinstance(old,ArrayValue) and old.items and isinstance(old.items[0],(int,float)):
                            new=copy.deepcopy(old);new.items[0]+=1
                        else:continue
                        altered=copy.deepcopy(seq['frames']);altered[index][key]=new
                        result=ltl.evaluate(item['formula'],altered,seq['atom'],init_snapshot=seq['initial'])
                        if not result.inconclusive and not result.holds:
                            found=dict(pid=p.pid,sid=item['sid'],group=seq['group'],case=seq['ids'][index],
                                changed_scan=index+1,output=key,old=tracer._plain(old),new=tracer._plain(new),counterexample_at=result.counterexample_at,
                                method='single copied output-snapshot perturbation')
                            break
            assert found,(p.pid,item['sid'],'property never detects any attempted output perturbation')
            controls.append(found)
    assert len(controls)==16 and sum(r['tests_total'] for r in rows)==1151
    assert Counter(r['status'] for r in formulas)==Counter(hold_on_test_traces=335,inconclusive=2)
    write(OUT/'references.json',rows);write(OUT/'formula_traces.json',formulas);write(OUT/'negative_controls.json',controls)
    suites=[]
    for pattern in ('test_v13_r7.py','test_v13_r6.py','test_v13_r5.py','test_v13_r4.py'):
        proc=subprocess.run([sys.executable,'-B','-X','utf8','-m','unittest','discover','-s','progress/tests','-p',pattern,'-q'],
            cwd=REPO,capture_output=True,text=True,encoding='utf-8',timeout=120)
        (OUT/(pattern+'.log')).write_bytes((proc.stdout+'\n'+proc.stderr).encode())
        assert proc.returncode==0,proc.stderr[-1400:]
        suites.append(dict(pattern=pattern,tests=int(re.search(r'Ran (\d+) tests?',proc.stderr)[1]),passed=True))
    native_path=REPO/'progress/evidence/v13_r6_20261110/native_references.json';native=load(native_path);cfg=load(v.ENGINE/'config.example.json')
    for cls in (CodesysBackend,OpenPLCBackend):
        backend=cls(cfg);identity=backend.identity()
        for p in v.problems():
            row=next(x for x in native if x['platform']==backend.name and x['pid']==p.pid)
            assert row['status']=='passed' and row['platform_identity']==identity and row['source_sha256']==v.digest(v.reference(p).encode())
    write(OUT/'native_references.json',[dict(row,reused=True,proof=native_path.relative_to(REPO).as_posix(),proof_sha256=v.digest(native_path.read_bytes())) for row in native])
    assert before==v.digest(LEDGER.read_bytes())
    write(OUT/'offline.json',dict(version=v.VERSION,data_version=v.DATA_VERSION,passed=True,cases=1151,cases_passed=1151,
        total_properties=361,runtime_ltl=337,suites=suites,formula_trace_statuses=dict(Counter(x['status'] for x in formulas)),
        negative_controls=16,native_reused=70,native_fresh=0,native_results_reused=True,model_calls=0,
        ledger_unchanged=True,ledger_sha256=before,human_review='r6_pending',
        data_note='r6功能数据与源码不变；仅修公式解析并补16条性质。335条通过测试轨迹，2条旧公式轨迹不足，未宣称完整形式证明。'))
    print('PASS 1151 reference cases,',sum(s['tests'] for s in suites),'checks, 16 negative controls, 70 native proofs reused')


def replay():
    mutable();before=v.digest(LEDGER.read_bytes());prior_path=REPO/'progress/evidence/v13_r6_rescore_20261110/rescore.json'
    prior=load(prior_path);data={p.pid:p for p in v.problems()};details=[];counts=Counter();diagnostics=Counter();failures=[]
    identity=CodesysBackend(load(v.ENGINE/'config.example.json')).identity()
    for old in prior['details']:
        path=REPO/'progress/evidence/v13_rescore_20261108b/candidates'/old['group']/(old['pid']+'.st')
        raw=path.read_bytes() if path.exists() else b'';assert v.digest(raw)==old['code_sha256']
        result=judge.local_tests(raw.decode(),data[old['pid']]) if raw else None
        previous=old['r6']
        native_reused=False
        if result and result.evidence_metadata.get('classification')=='unsupported_modeling' and previous['evidence_metadata'].get('classification')=='candidate_native_error':
            native=previous['platform_results']['codesys']
            assert native['status']=='failed' and native['platform_identity']==identity and native['source_sha256']==old['code_sha256']
            result.compiles=False;result.tests_passed=previous['tests_passed'];native_reused=True
        if result:
            assert (result.compiles,result.tests_passed,result.tests_total)==(previous['compiles'],previous['tests_passed'],previous['tests_total']),(old['group'],old['pid'])
        solved=bool(result and result.compiles and result.all_tests_passed)
        assert solved==old['r6_solved']
        category='no_code' if not raw else 'compile_or_native_error' if not result.compiles else 'passed' if solved else 'functional_failure'
        counts[category]+=1
        for diag in (previous or {}).get('compile_errors',[]):diagnostics[diag.get('code','unknown')]+=1
        if category=='functional_failure':
            bad=[c for c in result.cases if not c.passed]
            failures.append(dict(group=old['group'],pid=old['pid'],passed=result.tests_passed,total=result.tests_total,
                first_case=bad[0].tc_id,first_error=bad[0].message))
        details.append(dict(group=old['group'],pid=old['pid'],code_sha256=old['code_sha256'],frozen_attempt_index=old['frozen_attempt_index'],
            functional_solved=solved,tests_passed=result.tests_passed if result else 0,classification=category,native_failure_reused=native_reused))
    rows=[]
    for row in prior['rows']:
        rows.append(dict(group=row['group'],tasks=35,old_solved=row['new_solved'],new_solved=row['new_solved'],
            old_passed=row['new_passed'],new_passed=row['new_passed'],old_cases=1151,new_cases=1151,lost=[],gained=[],tool_errors=[]))
    assert len(details)==140 and before==v.digest(LEDGER.read_bytes())
    write(OUT/'functional_equivalence.json',dict(version=v.VERSION,baseline_label='r6功能',current_label='r7同一答案',rows=rows,
        details=details,fixed_source_bytes=True,same_functional_results=True,baseline_sha256=v.digest(prior_path.read_bytes()),
        model_calls=0,ledger_unchanged=True,note='Functional/native metric only; no claim that all formulas hold for these candidates.'))
    write(OUT/'failure_triage.json',dict(counts=dict(counts),diagnostic_occurrences=dict(diagnostics),functional_failures=failures,
        scope='fixed 140 selected R8 source bytes, r6 functional suite; counts are submissions, diagnostics can overlap'))
    print('PASS unchanged functional results for 140 fixed answers:',dict(counts))


def bounded():
    mutable();before=v.digest(LEDGER.read_bytes());rows=[]
    tasks={x['pid'] for x in load(v.ROOT/'spec_overlay.json')}
    for p in v.problems():
        if p.pid not in tasks:continue
        p.mc_max_seconds=3.
        result=judge.evaluate(v.reference(p),p,model_check=True,timeout_s=5.)
        rows.append(dict(pid=p.pid,result=result.to_dict()))
        write(OUT/'bounded_diagnostic.json',dict(complete=False,seconds_per_task=3,rows=rows))
        print('bounded',p.pid,'hold',result.mc_specs_hold,'violated',result.mc_specs_violated,'inconclusive',result.mc_specs_inconclusive,
            'truncated',result.mc_truncated,flush=True)
    assert len(rows)==8 and before==v.digest(LEDGER.read_bytes())
    write(OUT/'bounded_diagnostic.json',dict(complete=True,seconds_per_task=3,outer_deadline=5,rows=rows,
        scope='Unchanged declared domains/depths, short diagnostic budget; not a complete proof',model_calls=0,ledger_unchanged=True))


def summarize():
    mutable();offline=load(OUT/'offline.json');triage=load(OUT/'failure_triage.json');bounded_data=load(OUT/'bounded_diagnostic.json')
    lines=['# r7公式检查修复与后续诊断','','修复发生在独立r7；r6的1151条功能断言、参考源码、候选源码和工艺选择保持不变。lym确认包仍针对相同r6工艺契约。',
        '', '## 根因与修复','',
        '- 文字NOT被词法器识别为标识符，旧解析器因此把NOT prev/NOT rising送入普通ST表达式求值。新层按否定算子解析，不改变prev和边沿的既有语义。',
        '- 数字开头的比较只消耗第一个数字，导致0 < prev(elementCount)等合法式剩余未读。新层完整收集比较表达式。',
        '- 当前337条中，321条沿用r6，另16条从r6暂存记录原样补入；20条工艺口径冲突性质继续暂存。完整性、未知变量隔离、未知函数拒绝、总时限与转换/RETURN支持保留。',
        '', '## 免费验收','',
        f'- 1151/1151参考断言，{sum(s["tests"] for s in offline["suites"])}项回归通过；双平台70份编译证据按同源码与当前编译器身份复用，没有重复编译。',
        '- 337条非空公式中335条通过参考测试轨迹，配方S4与灌装S2仍因未来轨迹不足而未决；另24条仿真性质。没有把短轨迹通过写成穷尽证明。',
        '- 每条新增性质均检出一项复制输出快照的扰动，16/16；该检查验证公式敏感性，不等同于16个完整ST错解或154个上游变异已复验。另有真实ST控制程序验证第五拍反例、转换/RETURN及错误性质隔离。',
        '- 同一140份历史答卷免费复验的功能结果完全不变：18、16、7、10；未选择新轮次，未生成新答卷，未按新公式宣称这些候选全部形式通过。',
        '', '## 失败分类','', '| 类别 | 题次 |','| --- | ---: |']
    labels={'no_code':'无可评代码','compile_or_native_error':'静态/原生编译失败','functional_failure':'编译后功能失败','passed':'功能整题通过'}
    for k,count in triage['counts'].items():lines.append(f'| {labels[k]} | {count} |')
    lines+=['','静态诊断出现次数（同一答卷可能多个）：'+json.dumps(triage['diagnostic_occurrences'],ensure_ascii=False),
        '', '## 八题短预算形式诊断','', '| 题号 | 已判未违反 | 违反 | 未决 | 截断 | 实际/完整深度 |','| --- | ---: | ---: | ---: | --- | --- |']
    for row in bounded_data['rows']:
        result=row['result'];mc=result['model_check'];meta=result['evidence_metadata'].get('r7_model_check',{})
        lines.append(f'| {row["pid"]} | {mc["specs_hold"]} | {mc["specs_violated"]} | {mc["specs_inconclusive"]} | {mc["truncated"]} | {meta.get("max_depth","—")}/{meta.get("complete_depth","—")} |')
    lines+=['','本次按原输入域与名义深度，每题3秒诊断、总进程5秒。预算截断保留，不解释为完整有界通过；未知/异常条目不改成成功。',
        '', '## 下一步','',
        '先接收lym对三个工艺分歧与三处参考修复的确认，按返回意见建立后续独立版本；其他交接包继续核验和采纳。',
        '现有失败优先区分生成缺失、声明/编译问题与已编译后的控制时序问题。修复策略先用已有源码与离线检查验证；新的付费诊断需要单独固定方案，原诊断累计上限44.011998元不变。',
        '本轮模型调用0；共享账本仍38.409603元、438事件。人工批准未增加；未调用PLCVerif或引入上游专用证明器。',
        '', 'lym确认包：[下载](../给lym的确认包_r6_20261110.zip)。包内仍是同一r6工艺契约，r7只新增检查能力及性质，不改变他要确认的输入输出规则。',
        '', '## 离线复现','', '冻结后执行完整性检查或回归即可；verify/replay/bounded等证据写入命令仅供冻结前使用，后续修改须建立独立新版本。',
        '', '```powershell','python -B -X utf8 progress/tools/v13_r7.py check',
        'python -B -X utf8 -m unittest discover -s progress/tests -p test_v13_r7.py -q','```','']
    (v.ROOT/'README.md').write_bytes(('\n'.join(lines)).encode())
    print('PASS r7 report')


def freeze():
    mutable();v.verify_parent();proof=load(OUT/'offline.json');assert load(OUT/'functional_equivalence.json')['same_functional_results']
    assert load(OUT/'bounded_diagnostic.json')['complete'] and (v.ROOT/'README.md').exists()
    assert proof['ledger_sha256']==v.digest(LEDGER.read_bytes())
    write(OUT/'acceptance.json',dict(version=v.VERSION,data_version=v.DATA_VERSION,cases=1151,cases_passed=1151,
        tests=sum(s['tests'] for s in proof['suites']),formulas=337,trace_passed=335,trace_inconclusive=2,
        negative_controls=16,native_reused=70,fixed_candidates=140,functional_scores_unchanged=True,
        model_calls=0,ledger_unchanged=True,human_review='r6_pending'))
    paths=[p for base in (v.ROOT,OUT) for p in base.rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.name!='status_viewer.json']
    paths += [Path(__file__),REPO/'progress/tests/test_v13_r7.py']
    write(v.ROOT/'snapshot_manifest.json',dict(version=v.VERSION,files={p.relative_to(REPO).as_posix():v.digest(p.read_bytes()) for p in sorted(paths)}))
    print('PASS frozen r7')


def check():
    v.verify_parent()
    for name,sha in load(v.ROOT/'snapshot_manifest.json')['files'].items():assert v.digest((REPO/name).read_bytes())==sha,name
    print('PASS r7 and frozen r6 parent')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('command',choices=['verify','replay','bounded','summarize','freeze','check'])
    globals()[parser.parse_args().command]()

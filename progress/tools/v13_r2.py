"""Build, validate and freeze the r2 delta without paid model access."""
from pathlib import Path
import argparse
import html
import importlib.util
import json
import re
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO/'progress/v13_r2'))
import r2_revision as v
import r2_judge as judge
from stbench.platforms import CodesysBackend, OpenPLCBackend
OUT = REPO/'progress/evidence/v13_r2_20261108'
SCORES = REPO/'progress/evidence/v13_r2_rescore_20261108'
LEDGER = Path('E:/PLC_Dev/evidence/dmxapi_budget_75.json')


def load(path): return json.loads(path.read_text('utf-8'))
def encoded(value): return (json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode()
def write(path, value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(encoded(value))


def no_frozen_write():
    if (v.ROOT/'snapshot_manifest.json').exists():
        raise RuntimeError('r2 is frozen; use check or a new revision')


def review_inputs():
    origin=load(v.ROOT/'ORIGIN_R1.json')
    for name, expected in origin['source_reviews'].items():
        data=(REPO/'11.8 复核记录+意见'/name).read_bytes()
        assert v.digest(data)==expected
        p=OUT/'inputs'/name
        if p.exists(): assert p.read_bytes()==data
        else:
            p.parent.mkdir(parents=True,exist_ok=True)
            with p.open('xb') as f:f.write(data)


def build(do_write):
    if do_write:no_frozen_write()
    tasks=v.definitions();assert len(tasks)==35 and sum(len(d['test_cases']) for d in tasks)==531
    files={}
    for d in tasks:
        relative=f'{d["source"]}/{d["pid"]}.json'
        files[relative]=(v.PARENT/'datasets'/relative).read_bytes() if d['source']=='public' else encoded(d)
    for source in ('public','selfmade'):
        files[source+'/_index.json']=encoded([dict(pid=d['pid'],n_cases=len(d['test_cases']),n_specs=len(d['specs']),
            n_ltl=sum(bool(s['ltl']) for s in d['specs'])) for d in tasks if d['source']==source])
    with tempfile.TemporaryDirectory(prefix='plc_r2_') as directory:
        for relative,data in files.items():
            p=Path(directory)/relative;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
        for relative,data in files.items():
            p=v.ROOT/'datasets'/relative
            if do_write:p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
            else:assert p.read_bytes()==data,'Dataset drift: '+relative
    assert {p.relative_to(v.ROOT/'datasets').as_posix() for p in (v.ROOT/'datasets').glob('*/*.json')}==set(files)
    if do_write:
        review_inputs()
        contracts=[]
        for platform in ('codesys','openplc'):
            for p in v.problems():
                q,source,mapping=v.adapt(p,platform=platform)
                _,error=judge.prepare(q);assert error is None,p.pid
                name=f'adapted/{platform}/{p.pid}_{platform}.json'
                payload=encoded(q.to_dict());target=v.ROOT/name
                target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(payload)
                contracts.append(dict(pid=p.pid,platform=platform,path=name,sha256=v.digest(payload),
                    original_sha256=q.provenance['dataset_contract']['original_sha256'],
                    interface_changed=q.provenance['dataset_contract']['interface_changed'],
                    cases=len(q.test_cases),reference_sha256=v.digest(source.encode())))
        write(v.ROOT/'contracts_manifest.json',dict(version=v.VERSION,kind='platform_adapted',contracts=contracts,
            warning='These are derived platform contracts, not original VARIANT conformance results'))
    print('PASS build',len(tasks),'tasks / 531 cases',flush=True)


def verify():
    no_frozen_write();before=v.digest(LEDGER.read_bytes());build(False)
    audit_path=REPO/'progress/tools/audit_review_20261108.py'
    spec=importlib.util.spec_from_file_location('r2_formula_replay',audit_path)
    audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)
    rows=[]
    for p in v.problems():
        q,source,_=v.adapt(p);r=judge.local_tests(source,q)
        row=dict(pid=p.pid,compiles=r.compiles,tests_passed=r.tests_passed,tests_total=r.tests_total,
            errors=r.compile_errors,failures=[c.to_dict() for c in r.cases if not c.passed])
        if p.pid in v.FIVE:row['formula_replay']=audit.replay(q,source)
        rows.append(row)
    assert all(r['compiles'] and r['tests_passed']==r['tests_total'] for r in rows)
    assert all(s.get('holds') and not s.get('error') for r in rows for s in r.get('formula_replay',{}).get('formulas',[]))
    suites=[]
    for pattern in ('test_v13_review.py','test_v13_r2.py'):
        result=subprocess.run([sys.executable,'-B','-X','utf8','-m','unittest','discover','-s','progress/tests','-p',pattern,'-q'],
            cwd=REPO,capture_output=True,text=True,encoding='utf-8',timeout=90)
        (OUT/(pattern+'.log')).write_bytes((result.stdout+'\n'+result.stderr).encode())
        assert result.returncode==0,result.stderr[-1200:]
        count=int(re.search(r'Ran (\d+) tests?',result.stderr)[1]);suites.append(dict(pattern=pattern,tests=count,passed=True))
    native=[];cfg=load(v.ENGINE/'config.example.json')
    for cls in (CodesysBackend,OpenPLCBackend):
        backend=cls(cfg);identity=backend.identity()
        path=REPO/'progress/evidence/v13_review_20261108'/(backend.name+'_references.json')
        records=load(path);controls=path.with_name(backend.name+'_controls.json');assert load(controls)['passed']
        entries=[]
        for p in v.problems():
            q,code,_=v.adapt(p,platform=backend.name);digest=v.digest(code.encode())
            prior=next(r for r in records if r['pid']==p.pid)
            assert prior['status']=='passed' and prior['source_sha256']==digest and prior['platform_identity']==identity
            entries.append(dict(pid=p.pid,status='passed',source_sha256=digest,artifact_dir=prior['artifact_dir']))
        native.append(dict(platform=backend.name,source=path.relative_to(REPO).as_posix(),source_sha256=v.digest(path.read_bytes()),
            controls_sha256=v.digest(controls.read_bytes()),mode='reused exact reference source and current platform identity',entries=entries))
    runtime=[s for p in v.problems() for s in v.adapt(p)[0].specs]
    assert v.digest(LEDGER.read_bytes())==before
    write(OUT/'offline.json',dict(version=v.VERSION,passed=True,cases=531,cases_passed=531,total_properties=len(runtime),
        raw_ltl=sum(bool(s.ltl) for p in v.problems() for s in p.specs),runtime_ltl=sum(bool(s.ltl) for s in runtime),
        suites=suites,rows=rows,native_evidence=native,native_reference_passes=70,native_results_reused=True,
        judge_version=judge.JUDGE_VERSION,model_calls=0,ledger_unchanged=True,ledger_sha256=before,
        human_review='r2_pending; source review2 is a draft about upstream v1.3',
        formula_scope='given reference test sequences only; no exhaustive model-check claim'))
    print('PASS verify: 531/531; suites',sum(s['tests'] for s in suites),'; 70 native results revalidated',flush=True)


def rescore():
    no_frozen_write();assert not SCORES.exists(),'Use a new score output directory'
    before=v.digest(LEDGER.read_bytes());prior_path=REPO/'progress/evidence/v13_rescore_20261108b/rescore.json'
    prior=load(prior_path);problems={p.pid:p for p in v.problems()};groups={};details=[]
    for item in prior['details']:
        group,pid=item['group'],item['pid']
        row=groups.setdefault(group,dict(group=group,tasks=35,old_cases=531,new_cases=531,old_solved=0,new_solved=0,
            old_passed=0,new_passed=0,lost=[],gained=[],tool_errors=[]))
        path=prior_path.parent/'candidates'/group/(pid+'.st')
        code=path.read_bytes() if path.exists() else b'';assert v.digest(code)==item['code_sha256']
        p=problems[pid];q,_,_=v.adapt(p);error='';result=None
        if code:
            try:result=judge.local_tests(code.decode(),q)
            except Exception as exc:error=f'{type(exc).__name__}: {exc}'
        if result is not None and result.evidence_metadata.get('test_contract_valid') is False:
            raise RuntimeError('Invalid test contract must stop the study, not be scored as a model failure')
        ok=bool(result and result.compiles and result.all_tests_passed)
        old_ok=item['new_solved'];old_pass=item['new_local']['tests_passed'] if item['new_local'] else 0
        row['old_solved']+=int(old_ok);row['new_solved']+=int(ok);row['old_passed']+=old_pass
        row['new_passed']+=result.tests_passed if result else 0
        if old_ok and not ok:row['lost'].append(pid)
        if ok and not old_ok:row['gained'].append(pid)
        if error or item['new_evaluator_error']:row['tool_errors'].append(pid)
        details.append(dict(group=group,pid=pid,code_sha256=item['code_sha256'],frozen_attempt_index=item['frozen_attempt_index'],
            r1_passed=old_pass,r2=result.to_dict() if result else None,r1_solved=old_ok,r2_solved=ok,
            r1_error=item['new_evaluator_error'],r2_error=error))
    assert len(details)==140 and v.digest(LEDGER.read_bytes())==before
    write(SCORES/'rescore.json',dict(version=v.VERSION,baseline_version='v1.3-review-r1',baseline_label='r1 本地整题',
        current_label='r2 本地整题',baseline_score_sha256=v.digest(prior_path.read_bytes()),rows=list(groups.values()),details=details,
        fixed_candidates=True,model_calls=0,ledger_unchanged=True,
        scope='Post-hoc same fixed R8 candidates, r1 vs r2 local judge/data. No new generation, native candidate compilation or exhaustive LTL.'))
    lines=['# r1 → r2 固定候选重评分','','两侧同为531用例；沿用原冻结候选，不根据r2结果重选。模型调用为0。','',
        '| 组别 | r1整题 | r2整题 | r1用例 | r2用例 | 工具未决 |','| --- | ---: | ---: | ---: | ---: | ---: |']
    for r in groups.values():
        lines.append(f'| {r["group"]} | {r["old_solved"]}/35 | {r["new_solved"]}/35 | {r["old_passed"]}/531 | {r["new_passed"]}/531 | {len(r["tool_errors"])} |')
    lines+=['','这是平台适配口径下的本地事后评分，不替换R8正式结果。工具异常与缺失代码保留分母，不能解释为已确认模型错误。']
    (SCORES/'重评分结果.md').write_bytes(('\n'.join(lines)+'\n').encode())
    print(json.dumps(list(groups.values()),ensure_ascii=False),flush=True)


def freeze():
    no_frozen_write();proof=load(OUT/'offline.json');scores=load(SCORES/'rescore.json')
    assert proof['passed'] and len(scores['details'])==140
    v.verify_parent();v.r1.verify_engine()
    assert v.digest(LEDGER.read_bytes())==proof['ledger_sha256']
    sections=[]
    for p in v.problems():
        if p.pid not in v.FIVE:continue
        q,code,_=v.adapt(p)
        sections.append('<section><h2>'+html.escape(p.pid+' · '+p.title)+'</h2><h3>题面</h3><pre>'+html.escape(p.requirements)+
            '</pre><h3>适配后参考代码</h3><pre>'+html.escape(code)+'</pre><h3>用例</h3><pre>'+
            html.escape(json.dumps([c.to_dict() for c in q.test_cases],ensure_ascii=False,indent=2))+'</pre><h3>运行期规约</h3><pre>'+
            html.escape(json.dumps([s.to_dict() for s in q.specs],ensure_ascii=False,indent=2))+'</pre></section>')
    document='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>v1.3-review-r2 复审材料</title><style>body{font:16px/1.7 system-ui,"Microsoft YaHei",sans-serif;background:#f1f5fa;color:#203047;margin:0}main{max-width:1100px;margin:auto;padding:25px}section{padding:22px;background:white;margin:20px 0;border-radius:12px}pre{white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.7 Consolas,monospace;background:#f5f7fa;padding:15px}</style><main>
<h1>v1.3-review-r2 复审材料</h1><p>r2技术整改已完成，人工复审未签署。复核记录2标题标为草稿、对象为上游v1.3，其中火焰题标批准；这不作为本版批准。</p>
<p>本次新增修改：q45独立验证传感器失效拒绝复位；PI q7与收益q18注释修正；完整输出断言预检。531/531功能用例通过；参考代码未变，双平台证据按相同代码哈希与当前平台身份复用。公式仅在给定测试序列上复验。</p>
<p>以下为平台适配材料，原始VARIANT题、工作题与平台适配题的口径分开。原接口dt适配为scanSeconds，单位仍为秒。请填写同目录“复审记录.md”的本版结论及实际日期。</p>'''+''.join(sections)+'</main></html>'
    (v.ROOT/'复审材料.html').write_bytes(document.encode())
    acceptance=dict(version=v.VERSION,technical_passed=True,cases=531,cases_passed=531,
        tests=sum(s['tests'] for s in proof['suites']),suites=proof['suites'],native_reused=70,
        native_reuse_scope='unchanged reference source hashes and current native compiler identities verified',
        raw_ltl=proof['raw_ltl'],runtime_ltl=proof['runtime_ltl'],total_properties=proof['total_properties'],
        model_calls=0,ledger_unchanged=True,ledger_sha256=proof['ledger_sha256'],spent_cny=load(LEDGER)['spent_cny'],
        ledger_events=len(load(LEDGER)['events']),human_review='r2_pending',r1_and_engine_unchanged=True,
        full_output_guard='preflight data-contract rejection in local and worker entrypoints',
        comparison_scope='platform-adapted dataset only; original VARIANT conformance not claimed')
    write(OUT/'acceptance.json',acceptance)
    files=[p for p in v.ROOT.rglob('*') if p.is_file() and '__pycache__' not in p.parts]
    files += [Path(__file__),REPO/'progress/tests/test_v13_r2.py']
    write(v.ROOT/'snapshot_manifest.json',dict(version=v.VERSION,parent_manifest_sha256=load(v.ROOT/'ORIGIN_R1.json')['parent_manifest_sha256'],
        files={p.relative_to(REPO).as_posix():v.digest(p.read_bytes()) for p in sorted(files)},
        acceptance_sha256=v.digest((OUT/'acceptance.json').read_bytes()),
        evidence_sha256={p.relative_to(REPO).as_posix():v.digest(p.read_bytes()) for p in sorted(OUT.rglob('*')) if p.is_file() and p.name!='status_viewer.json'},
        rescore_sha256=v.digest((SCORES/'rescore.json').read_bytes()),human_review='r2_pending'))
    print(json.dumps(acceptance,ensure_ascii=False),flush=True)


def check():
    m=load(v.ROOT/'snapshot_manifest.json');v.verify_parent();v.r1.verify_engine();build(False)
    for name,expected in {**m['files'],**m['evidence_sha256']}.items():assert v.digest((REPO/name).read_bytes())==expected,name
    assert v.digest((OUT/'acceptance.json').read_bytes())==m['acceptance_sha256']
    assert v.digest((SCORES/'rescore.json').read_bytes())==m['rescore_sha256']
    print('PASS frozen r2, r1, engine and evidence hashes')


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('command',choices=['build','verify','rescore','freeze','check']);ap.add_argument('--write',action='store_true')
    args=ap.parse_args()
    if args.command=='build':build(args.write)
    else:globals()[args.command]()

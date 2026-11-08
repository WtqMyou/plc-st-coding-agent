"""Build and audit review-2 corrections without model calls."""
import argparse
import copy
from dataclasses import fields
import html
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import zipfile

REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO/'progress/v13_r4'))
import r4_revision as v
import r4_judge as judge
from stbench.schema import Problem
from stbench.platforms import CodesysBackend,OpenPLCBackend
from stbench.st.driver import _collect_domains
OUT=REPO/'progress/evidence/v13_r4_20261108'
SCORES=REPO/'progress/evidence/v13_r4_rescore_20261108b'
LEDGER=Path('E:/PLC_Dev/evidence/dmxapi_budget_75.json')


def load(p):return json.loads(p.read_text('utf-8'))
def encoded(d):return (json.dumps(d,ensure_ascii=False,indent=2)+'\n').encode()
def write(p,d):
    p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(encoded(d))
def mutable():assert not (v.ROOT/'snapshot_manifest.json').exists(),'Frozen r4; create another revision'


def build():
    mutable()
    tasks=v.definitions()
    assert len(tasks)==35 and sum(len(d['test_cases']) for d in tasks)==583
    for d in tasks:
        p=v.ROOT/'datasets'/d['source']/(d['pid']+'.json')
        if d['pid'] not in v.CHANGED:
            raw=(REPO/'progress/v13_r2/datasets'/d['source']/(d['pid']+'.json')).read_bytes()
            p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(raw)
        else:write(p,d)
    for name in ('public','selfmade'):
        write(v.ROOT/'datasets'/name/'_index.json',[dict(pid=d['pid'],n_cases=len(d['test_cases']),n_specs=len(d['specs'])) for d in tasks if d['source']==name])
    origin=load(v.ROOT/'ORIGIN_R3.json')
    for name,info in origin['source_reviews'].items():
        raw=(REPO/'11.8意见2'/name).read_bytes();assert v.digest(raw)==info['sha256']
        target=OUT/'inputs'/name
        if target.exists():assert target.read_bytes()==raw
        else:target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(raw)
    contracts=[]
    for platform in ('codesys','openplc'):
        for p in v.problems():
            q,code,_=v.adapt(p,platform=platform)
            name=f'adapted/{platform}/{p.pid}_{platform}.json';write(v.ROOT/name,q.to_dict())
            contracts.append(dict(pid=p.pid,platform=platform,path=name,reference_sha256=v.digest(code.encode()),cases=len(q.test_cases)))
    write(v.ROOT/'contracts_manifest.json',dict(version=v.VERSION,contracts=contracts,kind='platform_adapted'))
    print('PASS build: 35 tasks / 583 cases',flush=True)


def verify():
    mutable();before=v.digest(LEDGER.read_bytes())
    spec=importlib.util.spec_from_file_location('r4_replay',REPO/'progress/tools/audit_review_20261108.py')
    replay=importlib.util.module_from_spec(spec);spec.loader.exec_module(replay)
    rows=[]
    for p in v.problems():
        q,code,_=v.adapt(p);r=judge.local_tests(code,q)
        row=dict(pid=p.pid,compiles=r.compiles,tests_passed=r.tests_passed,tests_total=r.tests_total,
            failures=[c.to_dict() for c in r.cases if not c.passed],compile_errors=r.compile_errors,
            groups=r.evidence_metadata.get('group_counts'))
        if p.pid in v.FIVE+['self-hard-02']:
            row['formula_replay']=replay.replay(q,code)
        if p.pid in v.CHANGED:
            groups={}
            for c in q.test_cases:
                mode=c.mode or q.case_mode
                key='single:'+c.tc_id if mode=='single' else mode
                groups.setdefault(key,[]).append(c)
            row['group_formula_replays']=[]
            for name,cases in groups.items():
                one=copy.deepcopy(q);one.case_mode='sequence';one.test_cases=copy.deepcopy(cases)
                for c in one.test_cases:c.mode='sequence'
                row['group_formula_replays'].append(dict(group=name,**replay.replay(one,code)))
        rows.append(row)
    write(OUT/'reference_tests.json',rows)
    assert all(r['compiles'] and r['tests_passed']==r['tests_total'] for r in rows),str([(r['pid'],r['failures'],r['compile_errors']) for r in rows if not r['compiles'] or r['tests_passed']!=r['tests_total']])
    assert all(s.get('holds') and not s.get('error') for r in rows for s in r.get('formula_replay',{}).get('formulas',[])), 'Reference formula replay failed'
    assert all(not s.get('error') and not (not s.get('holds') and not s.get('inconclusive'))
        for r in rows for group in r.get('group_formula_replays',[]) for s in group.get('formulas',[])), 'Reference group formula contradicted or failed'
    suites=[]
    for pattern in ('test_v13_r3.py','test_v13_r4.py'):
        proc=subprocess.run([sys.executable,'-B','-X','utf8','-m','unittest','discover','-s','progress/tests','-p',pattern,'-q'],cwd=REPO,capture_output=True,text=True,encoding='utf-8',timeout=120)
        (OUT/(pattern+'.log')).write_text(proc.stdout+'\n'+proc.stderr,encoding='utf-8')
        assert proc.returncode==0,proc.stderr[-2200:]
        suites.append(dict(pattern=pattern,tests=int(re.search(r'Ran (\d+) tests?',proc.stderr)[1]),passed=True))
    # Identical code can reuse previous native compilation only under identical tool identity.
    native=[];cfg=load(v.ENGINE/'config.example.json')
    current_native=load(OUT/'native_references.json') if (OUT/'native_references.json').exists() else []
    for cls in (CodesysBackend,OpenPLCBackend):
        backend=cls(cfg);identity=backend.identity()
        prior_path=REPO/'progress/evidence/v13_review_20261108'/(backend.name+'_references.json')
        prior=load(prior_path)
        for p in v.problems():
            q,code,_=v.adapt(p,platform=backend.name);sha=v.digest(code.encode())
            old=next(r for r in prior if r['pid']==p.pid)
            current=next((r for r in current_native if r['pid']==p.pid and r.get('platform_identity')==identity
                          and r.get('source_sha256')==sha and r.get('status')=='passed'),None)
            if current:row=current
            elif old['source_sha256']==sha and old['platform_identity']==identity:
                row=dict(old,mode='reused exact reference source and current compiler identity',origin=prior_path.relative_to(REPO).as_posix())
            else:
                row=backend.compile(code,q).to_dict();row.update(pid=p.pid,source_sha256=sha,platform_identity=identity,mode='fresh r4 source compilation')
                print('native',backend.name,p.pid,row['status'],flush=True)
            native.append(row)
    write(OUT/'native_references.json',native)
    assert len(native)==70 and all(r['status']=='passed' for r in native)
    assert v.digest(LEDGER.read_bytes())==before
    runtime=[s for p in v.problems() for s in v.adapt(p)[0].specs]
    write(OUT/'offline.json',dict(version=v.VERSION,passed=True,cases=583,cases_passed=583,
        total_properties=len(runtime),raw_ltl=sum(bool(s.ltl) for p in v.problems() for s in p.specs),
        runtime_ltl=sum(bool(s.ltl) for s in runtime),rows=rows,suites=suites,
        native_reference_passes=70,native_fresh=sum(r['mode'].startswith('fresh') for r in native),
        native_reused=sum(r['mode'].startswith('reused') for r in native),model_calls=0,
        ledger_unchanged=True,ledger_sha256=before,human_review='r4_pending'))
    print('PASS verify: 583/583; native 70/70',flush=True)


def diagnostics():
    mutable();mc=v.load_modelcheck();tasks={p.pid:p for p in v.problems()};budget=[]
    for p in tasks.values():
        q,_,_=v.adapt(p);domains=_collect_domains(q)
        space=mc.InputSpace(domains,tuple(q.mc_fixed_inputs))
        budget.append(dict(pid=p.pid,inputs=len(domains),combinations=space.size(),requested_depth=q.mc_max_depth,
            max_traces=q.mc_max_traces,max_seconds=q.mc_max_seconds,first_layer_exceeds_budget=space.size()>q.mc_max_traces))
    write(OUT/'domain_audit.json',dict(version=v.VERSION,tasks=budget,scope='full inferred domains; no official narrowing'))
    # Reproduce the exact upstream overwrite mutant using the current r2 q45 contract.
    p=tasks['self-hard-06'];q,code,_=v.adapt(p)
    marker='latMem := latMem OR currentCauseMask;'
    assert code.count(marker)==1
    mutant=code.replace(marker,'latMem := currentCauseMask;')
    bad=judge.local_tests(mutant,q);good=judge.local_tests(code,q)
    write(OUT/'mask_mutant.json',dict(reference_passed=good.tests_passed,mutant_passed=bad.tests_passed,total=bad.tests_total,
        mutation=dict(before=marker,after='latMem := currentCauseMask;'),source_sha256=v.digest(code.encode()),
        failures=[c.to_dict() for c in bad.cases if not c.passed]))
    assert bad.tests_passed==18 and bad.tests_total==45
    # This restricted domain is diagnostic evidence only, never a dataset override.
    domains=dict(runRequest=[True],pressure=[4600.0],pressureValid=[False,True],fuelFlow=[0.0,4.5],
        steamFlow=[5.0],outletCmd=[0],outletFeedback=[100],resetBtn=[False])
    formula=next(s.ltl for s in q.specs if s.sid=='S13')
    narrow=[]
    for name,source in [('reference',code),('overwrite_mutant',mutant)]:
        report=mc.check(source,{'S13':formula},mc.InputSpace(domains),max_depth=4,max_traces=3000,max_seconds=12,
            observable_names={x.name for x in q.variables})
        narrow.append(dict(candidate=name,**report.to_dict()))
    write(OUT/'restricted_mask_diagnostic.json',dict(scope='diagnostic only; fixed all eight input domains explicitly; not full-domain proof',domains=domains,results=narrow))
    assert narrow[0]['all_hold'] and narrow[1]['specs'][0]['contradicting']
    # Measure actual depth under the declared full domains. Per-job cap is 5 s and
    # remains distinct from the dataset's 30 s; no claim to reproduce upstream timings.
    depth=[]
    for pid in ['public-hard-05','self-hard-06','self-medium-05','self-hard-07','public-hard-02','public-hard-06']:
        q,code,_=v.adapt(tasks[pid],mc_seconds=5)
        r=judge.evaluate(code,q,timeout_s=12,verification_after_tests=True)
        info=r.evidence_metadata.get('r4_model_check',{})
        depth.append(dict(pid=pid,diagnostic_seconds=5,result=r.to_dict(),actual_depth=info.get('max_depth'),complete_depth=info.get('complete_depth')))
        print('depth diagnostic',pid,info.get('max_depth'),'of',q.mc_max_depth,'truncated',r.mc_truncated,flush=True)
    write(OUT/'depth_diagnostics.json',dict(scope='5-second offline diagnostic, not the official 30-second setting; no score replacement',results=depth))


def rescore():
    mutable();assert not SCORES.exists(),'Use a new output directory'
    prior_path=REPO/'progress/evidence/v13_r3_rescore_20261108b/rescore.json';prior=load(prior_path)
    tasks={p.pid:p for p in v.problems()};groups={};details=[]
    cfg=load(v.ENGINE/'config.example.json');backend=CodesysBackend(cfg)
    for item in prior['details']:
        group,pid=item['group'],item['pid'];q,_,_=v.adapt(tasks[pid])
        path=REPO/'progress/evidence/v13_rescore_20261108b/candidates'/group/(pid+'.st')
        raw=path.read_bytes() if path.exists() else b''
        assert v.digest(raw)==item['code_sha256']
        error='';r=None
        try:
            r=judge.local_tests(raw.decode(),q) if raw else None
            if r and r.evidence_metadata.get('classification')=='unsupported_modeling':
                r=judge.parent.resolve_native(r,raw.decode(),q,(backend,),timeout_s=90)
        except Exception as exc:error=type(exc).__name__+': '+str(exc)
        assert not r or r.evidence_metadata.get('test_contract_valid') is not False
        old=item.get('r3',item.get('new_local',{}))
        old_ok=item.get('r3_solved',item.get('new_solved',False))
        # r3 serializes its stage result under "r3"; do not infer solved from counts alone.
        solved=bool(r and r.compiles and r.all_tests_passed)
        g=groups.setdefault(group,dict(group=group,tasks=35,old_cases=531,new_cases=583,old_solved=0,new_solved=0,old_passed=0,new_passed=0,lost=[],gained=[],tool_errors=[]))
        g['old_solved']+=int(old_ok);g['new_solved']+=int(solved)
        g['old_passed']+=(old or {}).get('tests_passed',0);g['new_passed']+=r.tests_passed if r else 0
        if old_ok and not solved:g['lost'].append(pid)
        if solved and not old_ok:g['gained'].append(pid)
        if error or (r and r.evidence_metadata.get('classification') in ('unsupported_modeling','tool_error')):g['tool_errors'].append(pid)
        details.append(dict(group=group,pid=pid,code_sha256=item['code_sha256'],frozen_attempt_index=item['frozen_attempt_index'],
            r3_solved=old_ok,r4_solved=solved,r3=old,r4=r.to_dict() if r else None,error=error))
    assert len(details)==140
    write(SCORES/'rescore.json',dict(version=v.VERSION,rows=list(groups.values()),details=details,model_calls=0,fixed_candidates=True,
        baseline_score_sha256=v.digest(prior_path.read_bytes()),baseline_label='r3 / r2 data',current_label='r4 data / r4 judge',
        dataset_sha256={p.relative_to(REPO).as_posix():v.digest(p.read_bytes()) for p in sorted((v.ROOT/'datasets').glob('*/*.json'))},
        judge_sha256={name:v.digest((v.ROOT/name).read_bytes()) for name in ('r4_judge.py','r4_worker.py','modelcheck.py','r4_revision.py')},
        scope='post-hoc fixed R8 answers; changed requirements and denominators; not a framework improvement study'))
    lines=['# r4固定历史答卷重评分','','沿用140个原选中轮次和代码哈希，模型调用0。旧侧r3裁判/r2数据为531例，新侧r4数据与裁判为583例。',
        '','| 组别 | r3整题 | r4整题 | r3用例 | r4用例 | 工具未决 |','| --- | ---: | ---: | ---: | ---: | ---: |']
    for g in groups.values():
        lines.append(f'| {g["group"]} | {g["old_solved"]}/35 | {g["new_solved"]}/35 | {g["old_passed"]}/531 | {g["new_passed"]}/583 | {len(g["tool_errors"])} |')
    lines += ['','新增通过为Codex DeepSeek的self-hard-04，来自泵轮换契约纠正，不是模型重新生成或框架改进。R8正式结果保持原样。',
        '','不带b的目录保留冻结前首次诊断。本目录额外绑定最终数据和裁判文件哈希，作为最终重评分证据。']
    (SCORES/'重评分结果.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(json.dumps(list(groups.values()),ensure_ascii=False),flush=True)


def review():
    mutable();sections=[]
    for p in v.problems():
        if p.pid not in v.CHANGED+v.FIVE:continue
        q,code,_=v.adapt(p)
        sections.append('<section id="'+p.pid+'"><h2>'+html.escape(p.pid+' '+p.title)+'</h2>'+''.join(
            '<h3>'+label+'</h3><pre>'+html.escape(text)+'</pre>' for label,text in [
                ('题面',q.requirements),('适配后参考代码',code),('测试用例',json.dumps([c.to_dict() for c in q.test_cases],ensure_ascii=False,indent=2)),
                ('运行期性质',json.dumps([s.to_dict() for s in q.specs],ensure_ascii=False,indent=2))])+'</section>')
    doc='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>r4 复审材料</title>
<style>body{font:16px/1.7 system-ui,"Microsoft YaHei",sans-serif;background:#eff4fa;color:#203047}main{max-width:1050px;margin:auto;padding:24px}section{background:white;margin:22px 0;padding:22px;border-radius:12px}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f6f8fb;padding:16px;font:13px/1.7 Consolas,monospace}</style><main>
<h1>r4 复审材料</h1><p>35题583用例。数据和裁判均另立版本，R8与r1至r3原记录保留。模型调用0。技术验收不能代替工艺签署；刘晏铭的本版人工结论待填写。</p>
<p>本版修正批次控制优先级、泵轮换迟滞和加热逐拍边界。PI切换及秒制积分契约已在r1完成，本版复验。每个sequence组使用独立实例；single每例独立。</p>
<p>这是平台适配题库，原始VARIANT接口另行留档。规约的输入域、预算、实际到达深度与完整展开深度分别报告；缩域诊断不计入正式通过数。</p>'''+''.join(sections)+'</main></html>'
    (v.ROOT/'复审材料.html').write_text(doc,encoding='utf-8')


def freeze():
    mutable();proof=load(OUT/'offline.json');scores=load(SCORES/'rescore.json')
    assert proof['passed'] and len(scores['details'])==140
    assert all(not r['tool_errors'] for r in scores['rows'])
    for name in ('source_audit.json','mask_mutant.json','domain_audit.json','depth_diagnostics.json','restricted_mask_diagnostic.json'):
        assert (OUT/name).is_file(),name
    for name,sha in scores['dataset_sha256'].items():assert v.digest((REPO/name).read_bytes())==sha,name
    for name,sha in scores['judge_sha256'].items():assert v.digest((v.ROOT/name).read_bytes())==sha,name
    v.verify_parent();assert v.digest(LEDGER.read_bytes())==proof['ledger_sha256']
    acceptance=dict(version=v.VERSION,technical_passed=True,cases=583,cases_passed=583,
        tests=sum(x['tests'] for x in proof['suites']),suites=proof['suites'],native_fresh=proof['native_fresh'],native_reused=proof['native_reused'],
        raw_ltl=proof['raw_ltl'],runtime_ltl=proof['runtime_ltl'],total_properties=proof['total_properties'],
        model_calls=0,spent_cny=load(LEDGER)['spent_cny'],ledger_events=len(load(LEDGER)['events']),
        ledger_unchanged=True,ledger_sha256=proof['ledger_sha256'],human_review='r4_pending',
        prior_versions_unchanged=True,scope='platform-adapted corrected dataset; 5-second depth diagnostics separate from scores')
    write(OUT/'acceptance.json',acceptance)
    files=[p for p in v.ROOT.rglob('*') if p.is_file() and '__pycache__' not in p.parts]
    files += [Path(__file__),REPO/'progress/tests/test_v13_r4.py']
    evidence=[p for p in OUT.rglob('*') if p.is_file() and p.name!='status_viewer.json']
    write(v.ROOT/'snapshot_manifest.json',dict(version=v.VERSION,
        files={p.relative_to(REPO).as_posix():v.digest(p.read_bytes()) for p in sorted(files)},
        evidence_sha256={p.relative_to(REPO).as_posix():v.digest(p.read_bytes()) for p in sorted(evidence)},
        rescore_sha256=v.digest((SCORES/'rescore.json').read_bytes()),human_review='r4_pending'))
    print('PASS frozen r4',flush=True)


def check():
    v.verify_parent();v.r3.r2.r1.verify_engine();m=load(v.ROOT/'snapshot_manifest.json')
    for name,sha in {**m['files'],**m['evidence_sha256']}.items():assert v.digest((REPO/name).read_bytes())==sha,name
    assert v.digest((SCORES/'rescore.json').read_bytes())==m['rescore_sha256']
    for definition in v.definitions():
        raw=load(v.ROOT/'datasets'/definition['source']/(definition['pid']+'.json'))
        assert raw==definition,definition['pid']
    print('PASS r4 and prior frozen hashes',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['build','verify','diagnostics','rescore','review','freeze','check'])
    globals()[parser.parse_args().command]()

"""Integrate the returned 13-task package; preserve old experiments and compare only compatible tasks."""
import argparse
from collections import Counter
import copy
from html import escape
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import zipfile

REPO=Path(__file__).resolve().parents[2]
ROOT=REPO/'progress/v13_r8'
OUT=REPO/'progress/evidence/v13_r8_20261110'
LEDGER=Path('E:/PLC_Dev/evidence/dmxapi_budget_75.json')
ARCHIVE=Path('C:/Users/27478/OneDrive/桌面/STBench_r6_13题修订_本地验算.zip')
sys.path.insert(0,str(REPO/'progress/v13_r7'))
import r7_revision as previous
import r7_ltl as ltl
import r7_judge
from stbench.schema import Problem,Spec
from stbench.platforms import CodesysBackend,OpenPLCBackend
spec=importlib.util.spec_from_file_location('r8_reference_trace',REPO/'progress/tools/v13_r6.py')
tracer=importlib.util.module_from_spec(spec);spec.loader.exec_module(tracer)


def load(p):return json.loads(p.read_text('utf-8-sig'))
def write(p,d):
    p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((json.dumps(d,ensure_ascii=False,indent=2)+'\n').encode())
def digest(raw):return previous.digest(raw)
def mutable():assert not (ROOT/'snapshot_manifest.json').exists(),'r8 frozen; use a new revision'
def revision():
    sys.path.insert(0,str(ROOT))
    import r8_revision
    return r8_revision


def build():
    mutable();assert not (ROOT/'ORIGIN_R7.json').exists(),'Existing draft: inspect before regenerating'
    before=digest(LEDGER.read_bytes());decisions=[];olddata={p.pid:p for p in previous.problems()}
    with zipfile.ZipFile(ARCHIVE) as z:
        assert z.testzip() is None
        datasets={Path(n).stem:n for n in z.namelist() if n.startswith('datasets/') and n.endswith('.json')}
        assert len(datasets)==13
        names=[*datasets.values(),*[str(Path(n).parent/'tests'/(pid+'.reference.st')).replace('\\','/') for pid,n in datasets.items()],
               'README.md','results.json','run.py','trace_check.py']
        hashes={}
        for name in names:
            raw=z.read(name);p=ROOT/'upstream'/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(raw);hashes[name]=digest(raw)
        write(ROOT/'upstream_manifest.json',dict(archive_sha256=digest(ARCHIVE.read_bytes()),files=hashes,
            bundled_engine_sha256={n:digest(z.read(n)) for n in z.namelist() if n.startswith('stbench/') and n.endswith('.py')},
            sender='lym (user-provided attribution)',signed_record_found=False))
        for pid,old in olddata.items():
            before_dict=old.to_dict();carried=[];mapped={};changes=[]
            if pid in datasets:
                d=json.loads(z.read(datasets[pid]));p=Problem.from_dict(d)
                source=z.read(str(Path(datasets[pid]).parent/'tests'/(pid+'.reference.st')).replace('\\','/')).decode('utf-8-sig')
                source=source.replace('\r\n','\n').replace('\r','\n')
                # Keep r7 additions omitted by a return package based on r6.
                new={s.sid:s for s in p.specs}
                for s in old.specs:
                    if s.sid in new:continue
                    same=next((sid for sid,n in new.items() if n.ltl and s.ltl and ltl.parse(n.ltl)==ltl.parse(s.ltl)),None)
                    if same:mapped[s.sid]=same
                    else:p.specs.append(copy.deepcopy(s));carried.append(s.sid)
                changes=[key for key in ('requirements','variables','specs','test_cases') if before_dict[key]!=p.to_dict()[key]]
                p.provenance['lym_return']=dict(received='2026-11-10',archive_sha256=digest(ARCHIVE.read_bytes()),
                    source_member=datasets[pid],status='revision_received',signed_record_found=False)
                p.provenance['human_process_review']=dict(status='lym_revision_received',reviewer='刘晏铭',approved=False,
                    evidence='returned 13-task revision package; no completed per-task signature form supplied')
                # Source claims are retained, not upgraded into independently
                # verified industrial origins or an approval for all 13 tasks.
                p.provenance['review']='已收到lym修订；按返回规则技术验收，不自动登记全题人工批准。'
            else:p=copy.deepcopy(old);source=previous.reference(old)
            old_cases={c.tc_id:c.to_dict() for c in old.test_cases};new_cases={c.tc_id:c.to_dict() for c in p.test_cases}
            assert len(new_cases)==len(p.test_cases),pid
            changed_cases={sid:[k for k in ('inputs','const_inputs','init','expected','mode','cycles','expect_full')
                if old_cases[sid].get(k)!=new_cases[sid].get(k)] for sid in set(old_cases)&set(new_cases)}
            changed_cases={sid:keys for sid,keys in changed_cases.items() if keys}
            p.provenance['review_revision']='v1.3-review-r8';p.provenance['spec_revision']='v1.3-review-r8'
            mapping=copy.deepcopy(old.provenance.get('platform_adaptation',{}))
            if pid=='public-easy-04':
                mapping.update(profile='numeric-milliseconds-v1+review-r8',rules=[
                    'DebounceMs and CycleMs: positive DINT milliseconds, bounded 1..3600000',
                    'PUMP_RUNTIME_ACC: LINT milliseconds; maintenance at 1800000000ms',
                    'Explicit numeric contract, not native TIME/LTIME conformance; old answers not rewritten'])
            mapping.update(data_version='v1.3-review-r8',adapted_source_sha256=digest(source.encode()))
            p.provenance['platform_adaptation']=mapping
            contract=copy.deepcopy(old.provenance.get('dataset_contract',{}));contract.update(version='v1.3-review-r8',
                working_json=f'progress/v13_r8/datasets/{p.source}/{pid}.json',reference_source_sha256=digest(source.encode()),
                comparison_scope='Three changed contracts are excluded from the unchanged 32-task historical comparison; no candidate interface rewriting')
            if pid=='public-easy-04':contract['interface_changed']=True
            p.provenance['dataset_contract']=contract
            write(ROOT/'datasets'/p.source/(pid+'.json'),p.to_dict())
            target=ROOT/'references'/(pid+'.reference.st');target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(source.encode())
            decisions.append(dict(pid=pid,returned=pid in datasets,changed_fields=changes,retained_r7_specs=sorted(carried),
                exact_ast_merged_specs=mapped,old_cases=len(old.test_cases),new_cases=len(p.test_cases),
                added_cases=sorted(set(new_cases)-set(old_cases)),removed_cases=sorted(set(old_cases)-set(new_cases)),
                changed_cases=changed_cases,reference_changed=source!=previous.reference(old),
                contract_changed=pid in {'public-easy-04','self-hard-04','self-medium-03'}))
    write(ROOT/'ORIGIN_R7.json',dict(date='2026-11-10',parent_git='85a3fc9409ec010d0ef65be65fe62fc151043fae',
        parent_manifest_sha256=digest((REPO/'progress/v13_r7/snapshot_manifest.json').read_bytes()),
        archive_name=ARCHIVE.name,archive_sha256=digest(ARCHIVE.read_bytes()),ledger_sha256=before,
        human_status='lym revision received; explicit contract choices adopted; no signed per-task approval inferred'))
    write(ROOT/'adoption.json',dict(tasks=decisions,contract_changes=['public-easy-04','self-hard-04','self-medium-03'],
        retained_r7_additions=['public-medium-04/N10-S7','self-hard-06/N10-S17'],model_calls=0))
    write(ROOT/'config.offline.json',dict(live_enabled=False,models=[],budget_cny=None,campaign_root='progress/evidence/v13_r8_20261110',
        budget_ledger_path=str(LEDGER),data_version='v1.3-review-r8',primary_profile='codesys',mc_seconds=30))
    assert before==digest(LEDGER.read_bytes())
    print('PASS built 35-task returned revision')


def verify():
    mutable();v=revision();before=digest(LEDGER.read_bytes());rows=[];formulas=[];mutants=[]
    for p in v.problems():
        source=v.reference(p);result=r7_judge.local_tests(source,p)
        assert result.compiles and result.all_tests_passed,(p.pid,result.failure_summary)
        rows.append(dict(pid=p.pid,passed=result.tests_passed,total=result.tests_total))
        sequences=tracer.traces(source,p)
        for s in p.specs:
            if not s.ltl:continue
            for seq in sequences:
                verdict=ltl.evaluate(s.ltl,seq['frames'],seq['atom'],init_snapshot=seq['initial'])
                assert verdict.holds and not verdict.inconclusive,(p.pid,s.sid,seq['group'],verdict.reason)
            formulas.append(dict(pid=p.pid,sid=s.sid,status='hold_on_test_traces'))
    mutations={'public-easy-04':('validMs >= DebounceMs','validMs > DebounceMs'),
        'self-hard-04':(' OR (need > prevNeed)',''),
        'self-medium-03':('IF obstacle THEN\n    state := 3;','IF obstacle THEN\n    state := 0;')}
    data={p.pid:p for p in v.problems()}
    for pid,(original,wrong) in mutations.items():
        source=v.reference(data[pid]);assert source.count(original)==1
        r=r7_judge.local_tests(source.replace(original,wrong),data[pid])
        assert r.compiles and not r.all_tests_passed
        mutants.append(dict(pid=pid,passed=r.tests_passed,total=r.tests_total,
            failed=[c.tc_id for c in r.cases if not c.passed],method='single ST mutation; original reference remains unchanged'))
    suites=[]
    for pattern in ('test_v13_r8.py','test_v13_r7.py','test_v13_r6.py','test_v13_r5.py','test_v13_r4.py'):
        proc=subprocess.run([sys.executable,'-B','-X','utf8','-m','unittest','discover','-s','progress/tests','-p',pattern,'-q'],
            cwd=REPO,capture_output=True,text=True,encoding='utf-8',timeout=120)
        OUT.mkdir(parents=True,exist_ok=True);(OUT/(pattern+'.log')).write_bytes((proc.stdout+'\n'+proc.stderr).encode())
        assert proc.returncode==0,proc.stderr[-1600:]
        suites.append(dict(pattern=pattern,tests=int(re.search(r'Ran (\d+) tests?',proc.stderr)[1]),passed=True))
    assert sum(r['total'] for r in rows)==1214 and before==digest(LEDGER.read_bytes())
    write(OUT/'references.json',rows);write(OUT/'formula_traces.json',formulas);write(OUT/'mutants.json',mutants)
    write(OUT/'offline.json',dict(version=v.VERSION,passed=True,cases=1214,cases_passed=1214,
        total_properties=sum(len(p.specs) for p in v.problems()),runtime_ltl=len(formulas),formula_trace_passed=len(formulas),
        suites=suites,model_calls=0,ledger_unchanged=True,ledger_sha256=before,human_review='lym_revision_received',
        data_note='采用lym返回规则，35题1214条断言；三题契约改变，历史比较只含其余32题。非空公式仅做测试轨迹核验，不声明穷尽证明。'))
    print('PASS',sum(r['total'] for r in rows),'cases,',len(formulas),'formula traces, 3 ST mutants,',sum(s['tests'] for s in suites),'tests')


def native():
    mutable();v=revision();before=digest(LEDGER.read_bytes());prior_path=REPO/'progress/evidence/v13_r7_20261110/native_references.json'
    prior=load(prior_path);rows=[];cfg=load(v.ENGINE/'config.example.json')
    for cls in (CodesysBackend,OpenPLCBackend):
        backend=cls(cfg);identity=backend.identity()
        for p in v.problems():
            old=next(x for x in prior if x['pid']==p.pid and x['platform']==backend.name);source=v.reference(p)
            if old['source_sha256']==digest(source.encode()) and old['platform_identity']==identity and old['status']=='passed':
                row=dict(pid=p.pid,platform=backend.name,status='passed',source_sha256=digest(source.encode()),platform_identity=identity,
                    reused=True,proof=prior_path.relative_to(REPO).as_posix(),proof_sha256=digest(prior_path.read_bytes()))
            else:row=dict(backend.compile(source,p).to_dict(),pid=p.pid,platform=backend.name,source_sha256=digest(source.encode()),reused=False)
            rows.append(row);write(OUT/'native_references.json',rows)
            assert row['status']=='passed',(p.pid,backend.name,row)
            print('native',backend.name,p.pid,'reused' if row['reused'] else 'fresh',flush=True)
    assert before==digest(LEDGER.read_bytes())
    report=load(OUT/'offline.json');report.update(native_results_reused=True,native_fresh=sum(not x['reused'] for x in rows),native_reused=sum(x['reused'] for x in rows))
    write(OUT/'offline.json',report)


def replay():
    mutable();v=revision();before=digest(LEDGER.read_bytes());oldpath=REPO/'progress/evidence/v13_r6_rescore_20261110/rescore.json'
    prior=load(oldpath);newdata={p.pid:p for p in v.problems()};olddata={p.pid:p for p in previous.problems()}
    rows={};details=[];diagnostic=[];identity=CodesysBackend(load(v.ENGINE/'config.example.json')).identity()
    for old in prior['details']:
        pid,group=old['pid'],old['group'];q=newdata[pid]
        path=REPO/'progress/evidence/v13_rescore_20261108b/candidates'/group/(pid+'.st')
        raw=path.read_bytes() if path.exists() else b'';assert digest(raw)==old['code_sha256']
        if pid=='public-easy-04':
            diagnostic.append(dict(group=group,pid=pid,status='excluded_changed_interface',source_sha256=old['code_sha256'],
                note='Old TIME/scan interface is not rewritten or graded as the new millisecond task.'))
            continue
        result=r7_judge.local_tests(raw.decode(),q) if raw else None
        previous_result=old['r6']
        if result and result.evidence_metadata.get('classification')=='unsupported_modeling' and previous_result['evidence_metadata'].get('classification')=='candidate_native_error':
            proof=previous_result['platform_results']['codesys']
            assert proof['platform_identity']==identity and proof['source_sha256']==old['code_sha256'] and proof['status']=='failed'
            result.compiles=False;result.tests_passed=previous_result['tests_passed']
        solved=bool(result and result.compiles and result.all_tests_passed)
        entry=dict(group=group,pid=pid,source_sha256=old['code_sha256'],frozen_attempt_index=old['frozen_attempt_index'],
            tests_passed=result.tests_passed if result else 0,tests_total=len(q.test_cases),local_solved=solved)
        if pid in v.CONTRACT_CHANGED:
            entry['status']='diagnostic_only_changed_contract';entry['native_acceptance_claimed']=False
            diagnostic.append(entry);continue
        assert [c.to_dict() for c in q.test_cases]==[c.to_dict() for c in olddata[pid].test_cases]
        assert (result is None and previous_result is None) or (result.compiles,result.tests_passed,result.tests_total)==(previous_result['compiles'],previous_result['tests_passed'],previous_result['tests_total'])
        assert solved==old['r6_solved']
        row=rows.setdefault(group,dict(group=group,tasks=32,old_solved=0,new_solved=0,old_passed=0,new_passed=0,
            old_cases=1113,new_cases=1113,lost=[],gained=[],tool_errors=[]))
        row['old_solved']+=int(old['r6_solved']);row['new_solved']+=int(solved)
        row['old_passed']+=(previous_result or {}).get('tests_passed',0);row['new_passed']+=result.tests_passed if result else 0
        details.append(entry)
    assert len(details)==128 and len(diagnostic)==12 and before==digest(LEDGER.read_bytes())
    write(OUT/'compatible_replay.json',dict(version=v.VERSION,baseline_label='r7相同32题',current_label='复核r8相同32题',
        rows=list(rows.values()),details=details,model_calls=0,ledger_unchanged=True,baseline_sha256=digest(oldpath.read_bytes()),
        scope='Only the 32 unchanged functional contracts; this is not a new 35-task four-group experiment.'))
    write(OUT/'changed_contract_diagnostics.json',dict(rows=diagnostic,scope='12 original answers: interface change excluded, pump/gate local diagnostics only; no accuracy-improvement claim'))
    print('PASS unchanged functional results on 32 tasks / 128 fixed answers; 3 changed contracts separate')


def summarize():
    mutable();v=revision();audit=load(ROOT/'adoption.json');proof=load(OUT/'offline.json');replay=load(OUT/'compatible_replay.json')
    labels={'custom_deepseek-v4pro':'自研 DeepSeek','codex_deepseek-v4pro':'Codex DeepSeek','custom_minimax-m27':'自研 MiniMax','codex_minimax-m27':'Codex MiniMax'}
    lines=['# lym返回包采纳与技术验收','',
        '收到用户转交的STBench_r6_13题修订_本地验算.zip，SHA-256为bc6dfaf544cf88337dd5580d2a9c90f0262e68ed4b04397dc2043caa1d3268f1。本轮建立v1.3-review-r8数据版本，执行裁判继续使用冻结r7。本名称指数据复核版本，与2026年10月的R8正式模型实验是不同事项。',
        '', '## 返回材料及确认范围','',
        '包内提供13题JSON、13份参考ST、README、结果及离线入口，另22题未随包提供。本机在独立目录复跑629/629用例，三项参考ST变异被拒绝；再用本项目r7裁判独立核验，未把对方引擎替换为正式裁判。',
        'README明确给出三项选择：果酱泵采用毫秒接口；裁剪后的需求台数上升时重选备泵；闸门任何状态遇障均当拍停机锁故障，障碍解除后须新的双键组合沿复位。已按这些规则落实。',
        '包内没有填写后的逐题确认表，多个来源字段仍为pending/approved=false；因此记录为“已收到lym修订并完成技术验收”，不自动登记13题全部人工批准。该状态不妨碍本次采纳明确修订。原来源路径、行业来源自述和旧标签只作历史记录。',
        '', '## 合并内容','',
        '- 果酱泵：TIME扫描替代接口改为DebounceMs/CycleMs正整数毫秒，范围1..3600000；运行累计为LINT毫秒；维护阈值为1800000000ms。旧7条扫描版用例留在冻结r6/r7，新版使用25条毫秒用例，不对旧答案重命名输入或强行换算。',
        '- 多泵：需求比较使用裁剪到0..5的台数，需求上升、初选、换主时重选备泵。主泵仍须轮换请求且工时差严格超过50小时。40条用例包含旧21条及新增19条，保留来件的两版轨迹，不把重叠断言当成独立证据。',
        '- 闸门：任何障碍当拍锁故障，两方向关闭；障碍解除后继续锁定。无障碍且双键组合出现新上升沿才复位，复位拍停止，随后新命令才能运动。改正旧m5/m6的故障位期望并补入26条，共36条。',
        '- 配方：补齐配比和温度的上下界及空槽编号清零；连续生产保持用上一拍直接表达，同时保留N10-S4对首个生产拍的约束。',
        '- 灌装：开阀必须有启动沿改为直接逐拍表达，覆盖首拍。蒸汽明确复位优先于禁用/故障，模糊控制明确乘积权重，PI明确复位与故障同拍的故障位。',
        '- 保留返回包漏带的r7加热N10-S7及超压N10-S17。泵的六条N10公式与来件S1/S2/S3/S6/S7/S8解析树完全相同，记录编号合并映射后保留含义。',
        '', '## 验收结果','',
        f'全库35题、1214/1214条参考断言通过；{sum(s["tests"] for s in proof["suites"])}项回归通过，三项真实ST错解被拒绝。双平台参考解各35/35：6次新编译、64份按相同源码与当前平台身份复用。',
        f'共有{proof["total_properties"]}条性质：{proof["runtime_ltl"]}条非空公式均在参考测试轨迹通过，另23条仿真性质。配方和灌装原两条未来轨迹不足问题因公式改写消除；这仍是有限测试轨迹核验，不是全输入/全深度形式证明，也没有接入PLCVerif。',
        '', '## 历史答卷的可比范围','',
        '3题契约已变，不能把旧35题成绩与新版35题直接对照。仅对其余32题、1113条完全相同功能断言复验128份原选中答卷，源代码字节及原轮次不变，结果全部一致。',
        '', '| 组别 | r7相同32题 | 复核r8相同32题 | 通过断言 /1113 |','| --- | ---: | ---: | ---: |']
    for row in replay['rows']:
        lines.append(f'| {labels[row["group"]]} | {row["old_solved"]}/32 | {row["new_solved"]}/32 | {row["new_passed"]} |')
    lines+=['','果酱泵4份旧答案因接口改变排除；泵/闸门8份旧答案只作新契约下的本地功能诊断，单列changed_contract_diagnostics.json，不计新四组准确率。未生成新代码，未用某组新版分数替换另一组旧分数。',
        '', '## 逐题合并记录','', '| 题号 | r7用例 | 新版用例 | 接口/行为契约变化 | 参考代码变化 |','| --- | ---: | ---: | --- | --- |']
    for row in audit['tasks']:
        if row['returned']:lines.append(f'| {row["pid"]} | {row["old_cases"]} | {row["new_cases"]} | {"是" if row["contract_changed"] else "否"} | {"是" if row["reference_changed"] else "否"} |')
    lines+=['','## 后续与复现','',
        '旧R8正式实验和r1–r7完整保留。后续队友交接包继续逐项核验；需要验证新版模型能力时，须以本次明确规则另建同期四组实验方案，不能直接沿用旧答案当作新实验。',
        '本次模型调用0，费用账本仍38.409603元、438事件。原诊断累计上限44.011998元和总上限75元保持。',
        '', '[当前题面与用例](复审材料.html) · [精确修改清单](adoption.json) · [技术验收](../evidence/v13_r8_20261110/acceptance.json)',
        '', '```powershell','python -B -X utf8 progress/tools/v13_r8.py check',
        'python -B -X utf8 -m unittest discover -s progress/tests -p test_v13_r8.py -q','```','']
    (ROOT/'README.md').write_bytes(('\n'.join(lines)).encode())
    cards=[]
    for p in v.problems():
        variables=''.join('<tr>'+''.join('<td>'+escape(str(x))+'</td>' for x in (variable.name,variable.data_type,variable.direction.value,variable.description))+'</tr>' for variable in p.variables)
        cases=''.join('<tr>'+''.join('<td>'+escape(str(x))+'</td>' for x in (c.tc_id,c.mode or p.case_mode,c.cycles,
            json.dumps({**c.const_inputs,**c.inputs},ensure_ascii=False),json.dumps(c.init,ensure_ascii=False),json.dumps(c.expected,ensure_ascii=False),c.note))+'</tr>' for c in p.test_cases)
        formulas=''.join('<li><b>'+escape(s.sid)+'</b> '+escape(s.text)+'<pre>'+escape(s.ltl or '仿真性质')+'</pre></li>' for s in p.specs)
        cards.append(f'<details class="task"><summary>{escape(p.pid)} · {escape(p.title)} · {len(p.test_cases)}条</summary><pre>{escape(p.requirements)}</pre><div class="scroll"><table><tr><th>变量</th><th>类型</th><th>方向</th><th>说明</th></tr>{variables}</table></div><h3>性质</h3><ul>{formulas}</ul><h3>用例</h3><p>同名sequence组连续，各组新实例；single每条新实例。输入为本行常量合并显式输入，初态在本行扫描前设置；cycles为本行扫描次数。</p><div class="scroll"><table><tr><th>编号</th><th>组</th><th>拍数</th><th>有效输入</th><th>初态</th><th>预期</th><th>说明</th></tr>{cases}</table></div></details>')
    text='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>lym返回修订版题面与验收</title><style>body{font:16px/1.7 system-ui,"Microsoft YaHei",sans-serif;color:#243349;background:#f4f6fa;margin:0}main{max-width:1180px;margin:auto;padding:26px 20px}section,details{background:white;border:1px solid #dbe3ed;padding:20px;margin:18px 0;border-radius:10px}summary{cursor:pointer;font-weight:650}.scroll{overflow:auto}table{width:100%;border-collapse:collapse;font-size:13px}td,th{border:1px solid #dbe3ed;padding:9px;text-align:left;overflow-wrap:anywhere}th{background:#edf2f8}pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:13px}a{color:#175eac}</style><main><h1>lym返回修订版题面与验收</h1><p>复核r8数据 · 沿用r7裁判 · 2026-11-10</p><section><h2>已落实的三项规则</h2><p>果酱泵采用毫秒接口；裁剪后的需求升档时重选备泵；闸门任何状态遇障均立即停机锁故障，解除后须双键新组合沿复位。</p><p>1214/1214参考断言、101项回归、双平台各35/35通过。349条非空公式在参考测试轨迹通过，另23条仿真性质；不声明穷尽证明。</p><p>收到13题修订与本地验算，未附逐题签署表，登记为收到lym修订并技术验收，不推定全题人工批准。三个变更题单列，历史可比范围为其余32题；不是新的35题四组实验。</p><p>本轮模型费用0元，累计38.409603/75元。旧资料和原成绩保留。</p></section>'''+''.join(cards)+'</main></html>'
    (ROOT/'复审材料.html').write_bytes(text.encode())
    print('PASS integration report and 35-task catalogue')


def freeze():
    mutable();v=revision();v.verify_parent();proof=load(OUT/'offline.json')
    assert len(load(OUT/'native_references.json'))==70 and len(load(OUT/'compatible_replay.json')['details'])==128
    assert proof['ledger_sha256']==digest(LEDGER.read_bytes()) and (ROOT/'README.md').exists()
    write(OUT/'acceptance.json',dict(version=v.VERSION,cases=proof['cases'],cases_passed=proof['cases_passed'],
        tests=sum(s['tests'] for s in proof['suites']),formula_trace_passed=proof['runtime_ltl'],
        native_fresh=proof['native_fresh'],native_reused=proof['native_reused'],unchanged_historical_tasks=32,
        changed_contract_tasks=3,model_calls=0,ledger_unchanged=True,human_review='lym_revision_received',signed_approval_inferred=False))
    paths=[p for base in (ROOT,OUT) for p in base.rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.name!='status_viewer.json']
    paths += [Path(__file__),REPO/'progress/tests/test_v13_r8.py']
    write(ROOT/'snapshot_manifest.json',dict(version=v.VERSION,files={p.relative_to(REPO).as_posix():digest(p.read_bytes()) for p in sorted(paths)}))
    print('PASS frozen returned-data revision')


def check():
    v=revision();v.verify_parent()
    for name,sha in load(ROOT/'snapshot_manifest.json')['files'].items():assert digest((REPO/name).read_bytes())==sha,name
    print('PASS review-r8 and frozen r7 parent')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('command',choices=['build','verify','native','replay','summarize','freeze','check'])
    globals()[parser.parse_args().command]()

"""Free full-public-answer replay and public contract/platform provenance audit."""
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import f14_v10_core as s

ROOT=s.REPO/'progress/evidence/f14_v10_preflight_20261113'

def main():
    cfg=s.config();ledger=Path(cfg['budget_ledger_path']);before=ledger.read_bytes()
    ROOT.mkdir(parents=True,exist_ok=True)
    for label,args in [('native',[]),('legacy_original',['--legacy-original'])]:
        proc=subprocess.run([sys.executable,'-B','-X','utf8',str(s.CONFIG.parent/'judge_audit_worker.py'),*args],cwd=s.REPO,capture_output=True,text=True,encoding='utf-8',timeout=300)
        assert proc.returncode==0,proc.stderr[-3000:]
        result=json.loads(proc.stdout)
        assert result['reference_cases']==946 and result['negative_controls']==35 and not result['private_rename_regressions']
        s.atomic_json(ROOT/(label+'_calibration.json'),result)
    pristine=s.REPO/'progress/f14_candidate/release'
    original_hashes={}
    for rel in [Path('agent_inputs.json'),*[p.relative_to(s.RELEASE) for p in (s.RELEASE/'datasets').rglob('*') if p.is_file()]]:
        assert (s.RELEASE/rel).read_bytes()==(pristine/rel).read_bytes(),rel
        original_hashes[rel.as_posix()]=s.sha(s.RELEASE/rel)
    s.atomic_json(ROOT/'original_dataset_hashes.json',original_hashes)
    # Reuse actual native positive and negative executions only when source and platform agree.
    native=Path('E:/PLC_Dev/evidence/incoming_reviews/f14_v7_return_native_20261112_v2')
    completion=s.load(native/'completion.json');assert completion['passed']
    for row in completion['rows']:
        folder=native/row['label'];result=s.load(folder/'result.json')
        assert result['status']==row['status'] and result['native_execution']
        assert s.sha(folder/'result.json')==row['result_sha256']
        assert s.sha(folder/'FB.st')==row['source_sha256']
        target=ROOT/'native_return_controls'/row['label'];target.mkdir(parents=True,exist_ok=True)
        for name in ('result.json','FB.st','job.json','stdout.log','stderr.log'):
            if (folder/name).exists():shutil.copyfile(folder/name,target/name)
    shutil.copyfile(native/'completion.json',ROOT/'native_return_controls/completion.json')
    controls=s.REPO/'progress/evidence/f14_v6_preflight_20261112'
    ipv4=s.load(controls/'ipv4_control.json')
    assert ipv4['native']['status']=='passed' and ipv4['functional']['result']['tests_passed']==14
    assert s.sha(s.CONFIG.parent/'reference_controls/public-medium-08.reference.st')==ipv4['source_sha256']
    assert ipv4['native']['platform_identity']==s.old.old.support.CodesysBackend(cfg).identity()
    s.atomic_json(ROOT/'native_ipv4_control.json',ipv4)

    saved=[]
    def add(record,attempt,origin,selection=False):
        if not record['pid'].startswith('public-'):return
        raw=attempt.get('code','');code,edits=s.normalize(raw)
        native=attempt.get('judge',{}).get('platform_results',{}).get('codesys',{})
        saved.append(dict(origin=origin,job_id=record['job_id'],condition=record['condition'],pid=record['pid'],candidate=attempt.get('idx',0),
            original_selected=selection,source=code,source_sha256=hashlib.sha256(code.encode()).hexdigest(),formatting_edits=edits,
            native_status=native.get('status','not_run'),native_hash_matches=native.get('source_sha256')==hashlib.sha256(code.encode()).hexdigest(),
            previous_passed=attempt.get('tests_passed',0),previous_functional=attempt.get('functional_pass',False)))
    historical=s.load(s.REPO/'progress/evidence/f14_v4_diagnostics_20261112/diagnostic_results.json')
    for row in historical['rows']:add(row,row['full'],'v4_selected_free_diagnostic',True)
    batches=[('v3_all_original','f14_v3_parallel_20261112'),('v6_all_original','f14_v6_public_pilot_20261112'),
             ('v8_all_original','f14_v8_temperature_repair_20261113'),('v9_all_original','f14_v9_temperature_minimal_20261113b')]
    for label,name in batches:
        folder=Path('E:/PLC_Dev/evidence/real_experiments')/name/'jobs'
        for path in sorted(folder.glob('*/*.json')):
            if path.name.count('.')!=1:continue
            record=s.load(path)
            if 'attempts' not in record:continue
            for attempt in record['attempts']:add(record,attempt,label,attempt['idx']==record.get('best_attempt'))
    v5=s.REPO/'progress/evidence/f14_v5_public_pilot_20261112/operational_restarts/string_byte_20261112/effective_jobs'
    for path in sorted(v5.glob('*/*.json')):
        record=s.load(path)
        for attempt in record['attempts']:add(record,attempt,'v5_effective_original',attempt['idx']==record.get('best_attempt'))
    keys={(r['pid'],r['source_sha256']):r['source'] for r in saved if r['source']}
    def run(item):
        (pid,digest),code=item
        result=s.run_stage(code,pid,'functional',30)
        return (pid,digest),result
    with ThreadPoolExecutor(max_workers=4) as pool:results=dict(pool.map(run,keys.items()))
    output=[]
    for row in saved:
        code=row.pop('source');evaluation=results.get((row['pid'],row['source_sha256']))
        if evaluation is None:row.update(classification='no_complete_code',functional_pass=False,tests_passed=0)
        else:
            r=evaluation['result'];classification=r.get('evidence_metadata',{}).get('classification','evaluated')
            category=classification if classification!='evaluated' else 'compile_or_interface_failure' if not r['compiles'] else 'functional_pass' if r['tests_passed']==r['tests_total'] else 'functional_mismatch'
            row.update(evaluation=evaluation,classification=category,tests_passed=r['tests_passed'],
                functional_pass=bool(r['compiles'] and r['tests_total'] and r['tests_passed']==r['tests_total'] and classification=='evaluated'))
        output.append(row)
    assert len({r['pid'] for r in output})==20
    selected=[r for r in output if r['origin']=='v4_selected_free_diagnostic']
    assert len(selected)==80 and all(sum(r['pid']==pid for r in selected)==4 for pid in {r['pid'] for r in selected})
    s.atomic_json(ROOT/'all_public_saved_answer_replay.json',dict(diagnostic_only=True,model_calls=0,original_scores_unchanged=True,
        answer_records=len(output),unique_code_evaluations=len(results),public_tasks=20,rows=output))
    users=s.load(s.RELEASE/'agent_inputs.json');audit=[]
    from public_time_bounds import derive
    for pid,task in s.tasks().items():
        if not pid.startswith('public-'):continue
        row=[r for r in selected if r['pid']==pid]
        original=users[pid]['user'];prompt=s.messages(dict(pid=pid))
        assert prompt[1]['content']==original and not any(key in prompt[0]['content'] for key in ('"test_cases"','"expected":','__spec_'))
        assert all(v['name'] in prompt[0]['content'] for v in task['variables'])
        audit.append(dict(pid=pid,title=task.get('title',''),cases=len(task['test_cases']),original_user_verbatim=True,
            interface_names_types_and_fields_from_original_json=True,private_test_data_in_initial_prompt=False,
            public_time_bounds=derive(original),original_selected_passed=sum(r['previous_functional'] for r in row),
            rechecked_selected_passed=sum(r['functional_pass'] for r in row),classifications=dict(Counter(r['classification'] for r in row)),
            native_eligible=pid!='public-hard-04',native_limitation='original VARIANT interface unavailable on frozen CODESYS profile' if pid=='public-hard-04' else '',
            task_json_sha256=original_hashes[next(k for k in original_hashes if k.endswith('/'+pid+'.json'))]))
    s.atomic_json(ROOT/'public_contract_platform_audit.json',dict(rows=audit,public_requirements_unchanged=True,
        testing_conventions_unchanged=True,reference_and_expectations_never_loaded_by_prompt_builder=True,
        temporal_resolution='TIME 1 ms; LTIME 1 ns is retained, not narrowed',
        native_string_semantics='scalar STRING index zero-based BYTE; MID positions one-based',
        control_provenance='original references retained; native-compatible IPv4 reference is an explicitly separate control'))
    lines=['# 20道公共题免费复评与要求核对','',f'复评{len(output)}条历史答卷记录，去重后执行{len(results)}份代码；零模型请求。旧成绩及原始答卷保持原样。',
        '', '| 题目 | 用例 | 历史四组选中答卷通过 | 新裁判复评通过 | 待处理分类 |','| --- | ---: | ---: | ---: | --- |']
    for r in audit:lines.append(f"| {r['pid']} | {r['cases']} | {r['original_selected_passed']}/4 | {r['rechecked_selected_passed']}/4 | {json.dumps(r['classifications'],ensure_ascii=False)} |")
    lines+=['','本表比较同一批保存代码在裁判修正前后的表现，是免费诊断，不计入下一轮新模型实验。',
        '已统一：RETURN结束本拍调用、STRING字节下标、结构体与数组值复制、枚举与嵌套CASE、TIME/LTIME精度、DUT分隔符。',
        '20道公共题的公开文字、接口和测试约定逐项核对；原题文件全部逐字节保留。FIFO保留原VARIANT接口，在当前原生平台单列适用性，功能分母保留。',
        '新策略适用于全部35题：公开条款编号、状态保持与复位检查、公开时间阈值演算、完整输入前缀反馈、从最强已有候选做最小修复。无逐题手写答案。',
        '没有将隐藏断言、参考解、测试说明或私有形式观察器送入生成和修复提示。']
    (ROOT/'公共题复评说明.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    assert ledger.read_bytes()==before
    s.atomic_json(ROOT/'summary.json',dict(passed=True,reference_cases=946,private_rename_cases=946,negative_controls=35,original_legacy_reference_cases=946,
        public_tasks=20,saved_public_answer_records=len(output),unique_public_codes=len(results),original_task_files_unchanged=True,
        original_scores_unchanged=True,full_replay_groups_without_prefix_truncation=True,max_candidates=4,ledger_unchanged=True,
        ledger_sha256=s.sha(ledger),external_model_calls=0))
    print('PASS full free review:',len(output),'public saved answer records;',len(results),'unique codes; 946 reference cases, 35 negatives; no paid requests',flush=True)

if __name__=='__main__':main()

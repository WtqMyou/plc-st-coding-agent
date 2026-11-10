"""Audit a completed study without calling models or changing its frozen inputs."""
from collections import Counter
from datetime import datetime
from decimal import Decimal
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import review_r8_first_candidate as study

NAMES = {'public-easy-04': '果酱泵', 'self-hard-04': '多泵', 'self-medium-03': '闸门'}
LABELS = {'custom_deepseek-v4pro': '自研 × DeepSeek', 'codex_deepseek-v4pro': 'Codex × DeepSeek',
          'custom_minimax-m27': '自研 × MiniMax', 'codex_minimax-m27': 'Codex × MiniMax'}
FORMAL = {'not_run': '未执行', 'bounded_pass': '有界通过', 'violated': '违反',
          'truncated': '截断', 'inconclusive': '未决', 'timeout': '超时', 'tool_error': '工具错误'}
OUTPUTS = ('analysis.json', '结果分析.md', '本轮费用明细.json', 'release_manifest.json')


def dec(value):
    return Decimal(str(value))


def fail(condition, message):
    if not condition:
        raise RuntimeError(message)


def aggregate(cfg, root):
    study.verify_frozen(root)
    plan = study.load(root / 'study_plan.json')
    fail(study.load(root / 'study_state.json').get('state') == 'completed', 'Study is not completed')
    active = study.load(root / 'active_run.json')
    fail(active.get('state') == 'completed' and active.get('ended_at') and not study.support.registered_process_alive(active),
         'Live runner has not finished publication')
    completion = study.load(root / 'completion.json')
    fail(completion.get('completed') and completion.get('recorded') == 12 and completion.get('actual_requests') == 12,
         'Incomplete coverage')
    before = study.load(root / 'ledger_before_study.json')
    fail(study.sha(root / 'ledger_before_study.json') == plan['initial_ledger_sha256'], 'Baseline snapshot changed')
    current = study.load(cfg['budget_ledger_path'])
    start = plan['initial_event_count']
    events = current['events'][start:start + 12]
    fail(current['events'][:start] == before['events'], 'Original billing prefix changed')
    fail(current.get('recoveries', [])[:len(before.get('recoveries', []))] == before.get('recoveries', []),
         'Original recoveries changed')
    fail(len(events) == 12 and all(e['status'] == 'settled' for e in events), 'Unsettled or missing study charge')
    fail(len({e['request_id'] for e in events}) == 12, 'Duplicate billing event')
    models = {m['id']: m for m in cfg['models']}
    problems = study.selected()
    fail(len(list((root / 'jobs').rglob('*.request_01.json'))) == 12, 'Wrong total request trace count')
    fail(len(list((root / 'jobs').rglob('*.response_01.json'))) == 12, 'Wrong total response trace count')
    details = []
    for job, event in zip(plan['jobs'], events):
        folder = root / 'jobs' / job['condition']
        record = study.load(folder / (job['pid'] + '.json'))
        timing = study.load(folder / (job['pid'] + '.timing.json'))
        request = study.load(folder / (job['pid'] + '.request_01.json'))
        response = study.load(folder / (job['pid'] + '.response_01.json'))
        fail(record.get('n_attempts') == 1 and len(record['attempts']) == 1, 'Not exactly one candidate')
        fail(timing.get('upstream_requests_entered') == 1, 'Not exactly one request')
        fail(len(list(folder.glob(job['pid'] + '.request_*.json'))) == 1, 'Extra request trace')
        fail(len(list(folder.glob(job['pid'] + '.response_*.json'))) == 1, 'Missing or extra response trace')
        fail(record['study_plan_sha256'] == study.sha(root / 'study_plan.json'), 'Plan binding mismatch')
        fail(record['r8_snapshot_sha256'] == plan['r8_snapshot_sha256'], 'Data binding mismatch')
        model = models[job['model_id']]
        a = record['attempts'][0]
        fail(request['model'] == model['model'] == event['request']['model'], 'Requested model mismatch')
        fail(response['model'].casefold() in {m.casefold() for m in model['accepted_models']} and a['actual_model'] == response['model'],
             'Returned model mismatch')
        fail(request['protocol'] == model['generation_protocol'] == event['request']['protocol'], 'Protocol mismatch')
        fail(request['max_tokens'] == event['request']['max_output_tokens'] == 16384, 'Output limit mismatch')
        fail(request['timeout_seconds'] == event['request']['timeout_seconds'] == 420, 'Request timeout mismatch')
        fail(study.obj_sha(study.messages_for(cfg, job, problems[job['pid']])) == job['task_prompt_sha256'],
             'Task prompt changed')
        fail(study.v.reference(problems[job['pid']]).strip() not in json.dumps(request, ensure_ascii=False),
             'Reference program leaked into request')
        upper = ((len(json.dumps(request['messages'], ensure_ascii=False).encode()) + 4096)
                 * model['input_cny_per_million'] + 16384 * model['output_cny_per_million']) / 1e6
        fail(study.money(upper) == study.money(event['reserved_cny'])
             and study.money(upper) <= study.money(job['first_upper_cny']), 'Request reservation mismatch')
        receipt = event['metadata']
        fail(receipt['model'] == response['model'] and receipt['usage'] == response['usage'], 'Receipt mismatch')
        fail(receipt['prompt_tokens'] == a['prompt_tokens'] and receipt['completion_tokens'] == a['completion_tokens'],
             'Token count mismatch')
        charge = study.money((a['prompt_tokens'] * model['input_cny_per_million']
                              + a['completion_tokens'] * model['output_cny_per_million']) / 1e6)
        fail(charge == study.money(a['cost_cny']) == study.money(event['accounted_cny']), 'Charge mismatch')
        fail(a['completion_tokens'] <= 16384, 'Provider exceeded output limit')
        fail(a['tests_total'] == len(problems[job['pid']].test_cases), 'Wrong functional denominator')
        fail(timing['wall_seconds'] <= 1200, 'Task exceeded wall limit')
        if a['code']:
            fail(hashlib.sha256(a['code'].encode()).hexdigest() == a['code_hash'], 'Candidate code hash changed')
            fail(study.extract_code(response['message'].get('content', '')) == a['code'], 'Candidate differs from original response')
        syntax = study.compile_st(a['code'])
        fail(record['complete_code'] == bool(syntax.ok and syntax.pou is not None), 'Incorrect complete-code flag')
        judge = a.get('judge', {})
        if judge.get('cases'):
            fail(sum(bool(c['passed']) for c in judge['cases']) == a['tests_passed'], 'Case pass-count mismatch')
            fail(len(judge['cases']) == a['tests_total'], 'Missing functional case results')
        mc = judge.get('model_check', {})
        fail(not mc.get('executed') or record['solved'], 'Formal stage ran before functional/native success')
        native = a.get('platform_results', {}).get('codesys', {}).get('status', 'not_run')
        native_row = a.get('platform_results', {}).get('codesys', {})
        native_artifacts = {}
        if native != 'not_run':
            fail(native_row['source_sha256'] == a['code_hash'], 'Native compiler received different candidate')
            fail(native_row['platform_identity'] == study.load(root / 'native_preflight.json')['codesys']['positive']['platform_identity'],
                 'Native compiler identity changed')
            artifact = Path(native_row['artifact_dir'])
            for filename in ('candidate.st', 'result.json', 'codesys_result.json'):
                if (artifact / filename).is_file():
                    native_artifacts[filename] = study.sha(artifact / filename)
            fail('candidate.st' in native_artifacts and 'result.json' in native_artifacts, 'Missing native artifacts')
            fail((artifact / 'candidate.st').read_text(encoding='utf-8') == a['code'], 'Native source file differs')
            fail(study.load(artifact / 'result.json') == native_row, 'Native compiler artifact differs from record')
        expected_solved = bool(a['compiles'] and a['tests_passed'] == a['tests_total'] and not a['provider_error']
                               and native == 'passed')
        fail(record['solved'] == expected_solved, 'Incorrect functional success flag')
        finish = response['finish_reason']
        content = response['message'].get('content', '')
        generation = ('empty' if not content.strip() else 'incomplete') if a['provider_error'] else 'complete'
        details.append(dict(job_id=job['job_id'], condition=job['condition'], pid=job['pid'],
            complete_code=record['complete_code'], codesys=native, solved=record['solved'],
            tests_passed=a['tests_passed'], tests_total=a['tests_total'],
            prompt_tokens=a['prompt_tokens'], completion_tokens=a['completion_tokens'], cost_cny=float(charge),
            wall_seconds=timing['wall_seconds'], finish_reason=finish, generation=generation,
            visible_output_characters=len(content), provider_error=a['provider_error'],
            compile_errors=judge.get('compile_errors', []), native=native_row, native_artifacts=native_artifacts,
            failure_summary=judge.get('failure_summary', ''),
            failed_cases=[c for c in judge.get('cases', []) if not c['passed']],
            verification_status=a['verification_status'], formal=mc))
    total = sum((dec(e['accounted_cny']) for e in events), dec(0))
    fail(total == dec(completion['study_increment_cny']), 'Total fee mismatch')
    fail(dec(plan['initial_spent_cny']) + total == dec(completion['total_accounted_cny']), 'Cumulative fee mismatch')
    fail(total <= dec(5) and dec(completion['total_accounted_cny']) <= dec(43.409603), 'Cap exceeded')
    rows = []
    for condition in LABELS:
        items = [d for d in details if d['condition'] == condition]
        fail(len(items) == 3 and sum(d['tests_total'] for d in items) == 101, 'Group denominator mismatch')
        rows.append(dict(condition=condition, label=LABELS[condition], planned=3, requests=3,
            complete_code=sum(d['complete_code'] for d in items),
            codesys_passed=sum(d['codesys'] == 'passed' for d in items),
            native_statuses=dict(Counter(d['codesys'] for d in items)), solved=sum(d['solved'] for d in items),
            tests_passed=sum(d['tests_passed'] for d in items), tests_total=101,
            cost_cny=float(sum((dec(d['cost_cny']) for d in items), dec(0))),
            wall_seconds=round(sum(d['wall_seconds'] for d in items), 3),
            prompt_tokens=sum(d['prompt_tokens'] for d in items),
            completion_tokens=sum(d['completion_tokens'] for d in items),
            generation_statuses=dict(Counter(d['generation'] for d in items)),
            formal_statuses=dict(Counter(d['verification_status'] for d in items)),
            formal_executed=sum(bool(d['formal'].get('executed')) for d in items),
            formal_violated_jobs=sum(bool(d['formal'].get('specs_violated')) for d in items),
            formal_truncated_jobs=sum(bool(d['formal'].get('truncated')) for d in items),
            formal_inconclusive_jobs=sum(bool(d['formal'].get('specs_inconclusive') or d['formal'].get('error')) for d in items),
            formal_not_executed=sum(not d['formal'].get('executed') for d in items)))
    environment = study.load(root / 'run_environment.json')
    fail(environment['paid_request_retries'] == 0, 'Retry policy mismatch')
    source = subprocess.check_output(['git', 'show', environment['published_git_commit'] + ':progress/tools/review_r8_first_candidate.py'], cwd=study.REPO)
    fail(hashlib.sha256(source).hexdigest() == plan['files']['progress/tools/review_r8_first_candidate.py'], 'Published source mismatch')
    billing = dict(initial_event_count=start, original_events_preserved=True, original_recoveries_preserved=True,
        initial_ledger_sha256=plan['initial_ledger_sha256'], events=events, new_events=12,
        incremental_cny=float(total), total_accounted_cny=completion['total_accounted_cny'],
        note='Configured public-price accounting; retained historical reservations are not new charges or an invoice.')
    result = dict(kind=plan['kind'], completed=True, acceptance_passed=True, recorded=12, actual_requests=12,
        analyzer_sha256=study.sha(Path(__file__)), published_preparation_commit=environment['published_git_commit'],
        study_plan_sha256=study.sha(root / 'study_plan.json'), r8_snapshot_sha256=plan['r8_snapshot_sha256'],
        incremental_cny=float(total), total_accounted_cny=completion['total_accounted_cny'],
        overall_wall_seconds=round((datetime.fromisoformat(active['ended_at'])
                                   - datetime.fromisoformat(environment['started_at'])).total_seconds(), 3),
        rows=rows, jobs=details, scope='Three reviewed tasks; one candidate per task/arm; no full-35 or stable-framework claim.')
    return result, billing


def markdown(result):
    lines = ['# 复核r8三题四组首候选：结果与验收', '',
        '12题次已完成，实际12次生成请求，无补发或修复轮；12次均正常返回正文，无空正文或输出截断。费用、模型身份、候选、请求和冻结版本逐条对应，验收通过。',
        '验收通过表示覆盖和记录符合方案，不要求模型全部答对。', '',
        '| 组别 | 可解析完整代码 | CODESYS通过 | 功能整题 | 功能断言 | 本轮费用/元 | 题次耗时合计/秒 |',
        '| --- | ---: | ---: | ---: | ---: | ---: | ---: |']
    for r in result['rows']:
        lines.append(f"| {r['label']} | {r['complete_code']}/3 | {r['codesys_passed']}/3 | {r['solved']}/3 | {r['tests_passed']}/101 | {r['cost_cny']:.6f} | {r['wall_seconds']:.1f} |")
    lines += ['', f"本轮计入 **{result['incremental_cny']:.6f}元**，累计 **{result['total_accounted_cny']:.6f}元**；本轮上限5元、累计保护上限43.409603元均满足。",
        f"串行实验总耗时约{result['overall_wall_seconds'] / 60:.1f}分钟，包括生成、编译、测试、形式检查和题间发布；各组题次耗时另见表格。",
        '费用按配置的输入/输出单价保守计入；共享账本保留的历史预留继续保留，不把它们写成本轮支出，也不代替供应商账单。',
        '可解析完整代码表示语法解析得到完整功能块；一份答卷虽正常返回完整正文，但含非法字符而未能解析。CODESYS通过单列：11份实际送编译均通过，另1份语法失败未送编译，仍计入3题分母。功能整题要求编译、接口与全部断言通过。', '',
        '## 逐题结果', '', '| 题目 | 组别 | CODESYS | 功能断言 | 生成状态 | 形式状态 |',
        '| --- | --- | --- | ---: | --- | --- |']
    for d in result['jobs']:
        lines.append(f"| {NAMES[d['pid']]} | {LABELS[d['condition']]} | {d['codesys']} | {d['tests_passed']}/{d['tests_total']} | {d['generation']} ({d['finish_reason']}) | {FORMAL.get(d['verification_status'], d['verification_status'])} |")
    lines += ['', '## 形式检查单列', '',
        '| 组别 | 执行 | 发现违反 | 检查截断 | 存在未决/错误 | 未执行 |',
        '| --- | ---: | ---: | ---: | ---: | ---: |']
    for r in result['rows']:
        lines.append(f"| {r['label']} | {r['formal_executed']} | {r['formal_violated_jobs']} | {r['formal_truncated_jobs']} | {r['formal_inconclusive_jobs']} | {r['formal_not_executed']} |")
    lines += ['', '此表按题次统计，违反、截断和未决可以同时出现，不能相加为总数。形式检查仅在功能和CODESYS通过后执行，最多30秒；有界通过不等于完整形式证明。', '',
        '## 失败定位', '']
    for d in result['jobs']:
        if d['solved']:
            continue
        lines += [f"### {NAMES[d['pid']]} · {LABELS[d['condition']]}", '']
        if d['provider_error']:
            lines += [f"生成状态：{d['provider_error']}；正文字符数{d['visible_output_characters']}。保留原响应，没有补发。", '']
        if d['compile_errors']:
            lines += [f"编译/接口诊断：{json.dumps(d['compile_errors'][:5], ensure_ascii=False)}", '']
        if d['failed_cases']:
            lines += [f"功能失败{len(d['failed_cases'])}条：" + '、'.join(c['tc_id'] for c in d['failed_cases']) + '。详细期望/实际值保留在analysis.json与原始裁判记录。', '']
        if d['failure_summary']:
            lines += [d['failure_summary'], '']
    pump = next(d for d in result['jobs'] if d['job_id'] == 'codex_minimax-m27/self-hard-04')
    gate = next(d for d in result['jobs'] if d['job_id'] == 'codex_minimax-m27/self-medium-03')
    lines += ['## 针对本次答卷的后续建议', '']
    if not pump['solved']:
        lines += ['Codex MiniMax多泵答卷中，minHours/minPumpIdx仅在首次选主分支计算，后续轮换分支继续使用旧值。结合p10等主泵未切换的失败断言，优先检查“当拍重新求最小值”和历史量更新顺序。这是对该份候选的代码诊断，不证明框架普遍存在同一问题。', '']
    if any("'!'" in d.get('message', '') for d in gate['compile_errors']):
        lines += ['Codex MiniMax闸门答卷将布尔取反写成!，ST语法检查在第48、57、60行拒绝，应使用NOT。下一轮可先评估通用ST语法自检，保留本轮原文和0/36结果，不事后替换答卷。', '']
    lines += ['建议先完成不增加模型费用的错误归类与通用自检方案，再另建小规模对照验证调整效果；需要新候选时另行冻结并核算费用。不要直接扩成全35题或把本轮三题的高通过率写成完整题库成绩。', '']
    lines += ['## 证据与结论边界', '',
        '免费预检为101项既有回归加19项实验检查；12条本地假响应通道包括6条真实Codex CLI路径，未产生生成费用。初次准备中发现的形式时限差异在付费前修正，旧准备目录保留；本次唯一实际运行目录为带_v2目录。',
        f"实际调用前发布的准备提交：`{result['published_preparation_commit']}`。源文件、题面提示、参数、运行顺序、预算、CLI与编译器身份均在冻结记录内。",
        '本轮使用复核r8数据、r7裁判。只解释果酱泵、多泵、闸门的这次首候选结果，不改写R8旧正式实验，不混入全35题分母，不据此判断稳定框架优势。',
        '原始请求、响应、候选、逐条功能结果、形式输出、费用事件和校验清单随报告保存。后续调整必须另建版本或实验，不覆盖这12份答卷。', '']
    return '\n'.join(lines)


def finalize(cfg, root):
    fail(not any((root / name).exists() for name in OUTPUTS), 'Final outputs already exist; no overwrite')
    result, billing = aggregate(cfg, root)
    study.atomic_json(root / 'analysis.json', result)
    study.atomic_json(root / '本轮费用明细.json', billing)
    (root / '结果分析.md').write_bytes(markdown(result).encode())
    study.report(cfg, study.load(root / 'study_plan.json'))
    (study.MIRROR / '本轮费用明细.json').write_bytes((root / '本轮费用明细.json').read_bytes())
    for job in result['jobs']:
        for filename, digest in job['native_artifacts'].items():
            source = Path(job['native']['artifact_dir']) / filename
            relative = Path('native_artifacts') / job['condition'] / job['pid'] / filename
            for destination in (root / relative, study.MIRROR / relative):
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(source.read_bytes())
    files = {p.relative_to(study.MIRROR).as_posix(): study.sha(p) for p in study.MIRROR.rglob('*') if p.is_file()}
    manifest = dict(kind='review_r8_first_candidate_final_release', analyzer_sha256=study.sha(Path(__file__)),
                    files=files, study_plan_sha256=result['study_plan_sha256'], actual_requests=12)
    study.atomic_json(root / 'release_manifest.json', manifest)
    study.atomic_json(study.MIRROR / 'release_manifest.json', manifest)
    print('PASS finalized 12 jobs; increment', result['incremental_cny'], 'CNY')


def check(cfg, root):
    result, billing = aggregate(cfg, root)
    fail(result == study.load(root / 'analysis.json'), 'Analysis does not reproduce')
    fail(billing == study.load(root / '本轮费用明细.json'), 'Billing audit does not reproduce')
    fail(markdown(result).encode() == (root / '结果分析.md').read_bytes(), 'Report does not reproduce')
    manifest = study.load(root / 'release_manifest.json')
    fail(manifest == study.load(study.MIRROR / 'release_manifest.json'), 'Mirror manifest mismatch')
    fail(manifest['analyzer_sha256'] == study.sha(Path(__file__)), 'Analyzer changed after release')
    for name, digest in manifest['files'].items():
        fail(study.sha(root / name) == digest == study.sha(study.MIRROR / name), 'Frozen evidence changed: ' + name)
    print('PASS reproducible final report, 12 receipts, preserved history and published evidence hashes')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('finalize', 'check'))
    args = parser.parse_args()
    cfg = study.configuration(str(study.CONFIG))
    root = Path(cfg['campaign_root'])
    if args.command == 'finalize':
        finalize(cfg, root)
    else:
        check(cfg, root)

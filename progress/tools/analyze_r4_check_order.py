"""Summarize only a completed, immutable r4 pilot; no generation or billing writes."""
from collections import Counter
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import r4_check_order as study


def object_sha(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,ensure_ascii=False).encode()).hexdigest()


def main():
    cfg=study.configuration(str(study.CONFIG));root=Path(cfg['campaign_root'])
    study.verify_frozen(root);plan=study.load(root/'study_plan.json')
    if study.load(root/'study_state.json').get('state')!='completed':
        raise RuntimeError('Wait for all planned jobs; partial output must not be called final')
    assert not (root/'analysis.json').exists(),'Existing analysis is immutable; use a new version'
    summary=study.collect(cfg,plan);assert summary['recorded']==8 and summary['all_original_events_preserved']
    ledger=study.load(cfg['budget_ledger_path']);events=ledger['events'][plan['initial_event_count']:]
    assert len(events)<=16 and all(e['status']=='settled' for e in events)
    assert not ledger.get('halted') and ledger['spent_cny']<=plan['cumulative_ceiling_cny']
    charged=sum(e['accounted_cny'] for e in events)
    assert abs(charged-summary['study_increment_cny'])<.000002
    details=[];requests={};stop_counts=Counter();verification=Counter();output=Counter()
    for job in plan['jobs']:
        folder=root/'jobs'/job['condition'];record=study.load(folder/(job['pid']+'.json'))
        assert record['r4_snapshot_sha256']==plan['r4_snapshot_sha256']
        assert record['study_plan_sha256']==study.sha(root/'study_plan.json')
        assert len(record['attempts'])<=2
        stop_counts[record['stop_reason']]+=1
        traces=sorted(folder.glob(job['pid']+'.request_*.json'))
        assert len(traces)<=2
        if traces:requests[(job['condition'],job['pid'])]=study.load(traces[0]).get('messages')
        outputs=[]
        for p in sorted(folder.glob(job['pid']+'.response_*.json')):
            r=study.load(p);message=r.get('message') or {};content=message.get('content') or ''
            reasoning=message.get('reasoning_content') or ''
            label='complete' if r.get('finish_reason') in ('stop','completed') and content.strip() else 'other'
            if r.get('finish_reason') in ('length','incomplete'):
                label='length_empty_with_reasoning' if not content.strip() and reasoning else 'length_other'
            output[label]+=1
            outputs.append(dict(path=p.relative_to(root).as_posix(),finish_reason=r.get('finish_reason'),
                content_characters=len(content),reasoning_characters=len(reasoning),classification=label,
                usage=r.get('usage'),sha256=study.sha(p)))
        for a in record['attempts']:verification[a.get('verification_status','not_run')]+=1
        best=next((a for a in record['attempts'] if a['idx']==record.get('best_attempt')),None)
        details.append(dict(job_id=job['job_id'],framework=job['framework'],pid=job['pid'],
            verification_after_tests=job['verification_after_tests'],solved=record['solved'],
            first_try=record['first_try'],best_attempt=record.get('best_attempt'),stop_reason=record['stop_reason'],
            attempts=len(record['attempts']),actual_requests=len(traces),
            mc_executed=sum(bool(a.get('judge',{}).get('model_check',{}).get('executed')) for a in record['attempts']),
            first_code_sha256=record['attempts'][0].get('code_hash') if record['attempts'] else None,
            best_tests_passed=best['tests_passed'] if best else 0,tests_total=record['tests_total'],outputs=outputs))
    assert sum(d['actual_requests'] for d in details)==len(events)
    pairs=[]
    for fw in ('custom','codex'):
        for pid in study.PIDS:
            a=next(d for d in details if d['framework']==fw and d['pid']==pid and not d['verification_after_tests'])
            b=next(d for d in details if d['framework']==fw and d['pid']==pid and d['verification_after_tests'])
            am=requests.get((fw+'_always_mc',pid));bm=requests.get((fw+'_tests_first',pid))
            pairs.append(dict(framework=fw,pid=pid,always_solved=a['solved'],tests_first_solved=b['solved'],
                first_code_identical=bool(a['first_code_sha256'] and a['first_code_sha256']==b['first_code_sha256']),
                first_actual_upstream_messages_identical=bool(am is not None and bm is not None and am==bm),
                first_upstream_message_sha256=dict(always=object_sha(am),tests_first=object_sha(bm))))
    result=dict(version='r4-check-order-20261108',complete=True,planned=8,recorded=8,rows=summary['rows'],
        details=details,pairs=pairs,stop_reasons=dict(stop_counts),verification_statuses=dict(verification),
        output_observations=dict(output),actual_model_requests=len(events),study_charged_cny=round(charged,6),
        total_accounted_cny=ledger['spent_cny'],all_original_events_preserved=True,
        ledger_sha256=study.sha(Path(cfg['budget_ledger_path'])),source_commit=study.load(root/'run_environment.json')['published_git_commit'],
        analyzer_sha256=study.sha(Path(__file__)),inference_limit='two tasks, one run per arm; different candidates and generation timing prevent causal attribution of wall-time or solved differences')
    study.atomic_json(root/'analysis.json',result)
    lines=['# r4检查顺序小试验结果分析','',
        '8/8题次完成。两题、MiniMax、两框架、两个形式检查条件。候选全部重新生成；不替换R8正式四组结果，也不与旧答案混作同一轮。','',
        '| 条件 | 首轮通过 | 最终通过 | 用例通过 | 修复新增 | 请求数 | 形式检查数 | 墙钟秒 |',
        '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for r in summary['rows']:
        lines.append(f"| {r['condition']} | {r['first_solved']}/2 | {r['solved']}/2 | {r['tests_passed']}/{r['tests_total']} | {r['repaired']} | {r['calls']} | {r['mc_executed']} | {r['wall_seconds']} |")
    lines += ['',f"实际模型请求{len(events)}/16次，本轮计入{charged:.6f}元，累计{ledger['spent_cny']:.6f}元；旧423条账本事件及恢复记录保持。未扩大费用上限，旧未知预留未冲销。",'',
        '各条件实际回复可能不同。下表核对首候选代码及真实上游消息是否相同，避免把候选差异当作检查顺序的收益。Codex CLI还可能带入不同的隔离工作目录等环境上下文。','',
        '| 框架 | 题号 | 持续检查通过 | 后置检查通过 | 首候选相同 | 实际首请求消息相同 |','| --- | --- | --- | --- | --- | --- |']
    for p in pairs:
        lines.append(f"| {p['framework']} | {p['pid']} | {p['always_solved']} | {p['tests_first_solved']} | {p['first_code_identical']} | {p['first_actual_upstream_messages_identical']} |")
    lines += ['','输出观测分类：'+json.dumps(dict(output),ensure_ascii=False)+'。',
        'length_empty_with_reasoning仅表示返回在长度上限处结束、正文为空而推理字段非空；不声称已证明提供方内部原因，不从推理字段拼装候选代码。',
        '','未执行形式检查、发生预算截断、存在反例、工具未判定分别保留。功能通过不等于形式性质全部通过。',
        '','本轮可确认新r4入口、受控CLI、计费保护与两轮修复流程是否跑通；13项离线检查已经用同一坏候选证明后置条件确实跳过形式检查。两题单次生成不能确认准确率或耗时的稳定因果收益。',
        '','下一步优先分析具体失败和输出截断。保留同一题库/裁判，后续只改变一个生成或调度参数；不得仅凭本轮通过数扩大成全量对照，也不自动追加预算。']
    (root/'结果分析.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    files=[p for p in root.rglob('*') if p.is_file() and
        (p.name in ('study_plan.json','prepared.json','validation.json','native_preflight.json','cli_offline.json',
                    'run_environment.json','study_summary.json','study_state.json','completion.json','analysis.json','结果分析.md','实验状态.md')
         or (p.relative_to(root).parts[0]=='jobs' and p.suffix=='.json'))]
    study.atomic_json(root/'result_manifest.json',dict(version=result['version'],files={p.relative_to(root).as_posix():study.sha(p) for p in sorted(files)},
        model_requests=len(events),ledger_sha256=result['ledger_sha256']))
    print(json.dumps(dict(completed=True,model_requests=len(events),stage_cny=round(charged,6),rows=summary['rows']),ensure_ascii=False))


if __name__=='__main__':main()

"""Separate diagnostic evidence from fresh twenty-task independent validation."""
from html import escape
from pathlib import Path
import json
import zipfile
import f14_v13_core as s
from f14_v11_status import copy_changed

def report(cfg,plan):
    root=Path(cfg['campaign_root']);mirror=s.MIRROR;mirror.mkdir(parents=True,exist_ok=True)
    ledger=s.load(cfg['budget_ledger_path']);state=s.load(root/'study_state.json');rows=[]
    for phase in ('diagnostic','full'):
        jobs=[j for j in plan['jobs'] if j['phase']==phase]
        records=[s.load(root/'jobs'/j['condition']/(j['pid']+'.json')) for j in jobs]
        records=[r for r in records if r];best=[r['attempts'][r['best_attempt']] for r in records if r.get('best_attempt') is not None]
        first=[r['attempts'][0] for r in records if r['attempts']]
        rows.append(dict(phase=phase,planned=len(jobs),completed=sum(r['job_done'] for r in records),
            functional_passed=sum(a['functional_pass'] for a in best),first_passed=sum(a['functional_pass'] for a in first),
            native_passed=sum(a['native_pass'] for a in best),assertions_passed=sum(a['tests_passed'] for a in best),
            assertions_total=sum(len(s.tasks()[j['pid']]['test_cases']) for j in jobs),
            requests=sum(len(r['attempts']) for r in records),
            results=[dict(pid=r['pid'],done=r['job_done'],passed=r['attempts'][r['best_attempt']]['tests_passed'] if r.get('best_attempt') is not None else 0,total=r['tests_total']) for r in records]))
    summary=dict(state=state,rows=rows,accounted_cny=ledger['spent_cny'],cap_cny=420,
        new_accounted_cny=float(s.money(ledger['spent_cny'])-s.money(s.BASELINE)),halt_reason=ledger.get('halted',''),
        updated_at=s.stamp(),maximum_requests=88,other_groups_paused=True)
    lines=['# V13 DeepSeek自研公共题验证','',f"阶段：{state.get('state')} / {state.get('phase','准备')}；累计计入 {ledger['spent_cny']:.6f}/420元。",'',
        '机械臂54/54和温控37/37已自主修复并免费复验；本阶段验证灌装线和FIFO，再用同一冻结版助手独立生成20题。两部分分别统计，首轮全量不注入旧答卷或针对性验证代码。',
        '最多8题并行；每题最多4候选；输出上限24576；其他三组保持暂停。','',
        '| 阶段 | 完成 | 功能整题通过 | 用例通过 | 请求 |','| --- | ---: | ---: | ---: | ---: |']
    for row in rows:lines.append(f"| {'灌装线与FIFO验证' if row['phase']=='diagnostic' else '20题独立全量'} | {row['completed']}/{row['planned']} | {row['functional_passed']}/{row['planned']} | {row['assertions_passed']}/{row['assertions_total']} | {row['requests']} |")
    lines+=['','功能题数包含原VARIANT FIFO；原生编译单列19道适配题。模型生成的精确补丁、原始回复、完整候选及反馈均保留。',
        '完整最坏新增预留：'+str(plan['worst_reservation_cny'])+'元；预留不等于实际花费。',
        '停止原因：'+ledger.get('halted',''),'更新：'+summary['updated_at'],'']
    for row in rows:
        lines.append(('修复验证' if row['phase']=='diagnostic' else '独立全量')+'逐题：')
        lines.extend(f"- {v['pid']}：{v['passed']}/{v['total']}，{'完成' if v['done'] else '运行中'}" for v in row['results'])
    text='\n'.join(lines)+'\n';s.atomic_json(root/'status.json',summary);(root/'实验状态.md').write_text(text,encoding='utf-8')
    html='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta http-equiv="refresh" content="15"><title>V13 自研验证</title><style>body{font:16px/1.8 system-ui;max-width:1100px;margin:30px auto;padding:20px;background:#f3f6fb}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:white;padding:24px;border-radius:12px}</style><h1>DeepSeek 自研公共题验证</h1><pre>'+escape(text)+'</pre></html>'
    (root/'status.html').write_text(html,encoding='utf-8')
    for p in root.glob('*'):
        if p.is_file() and p.suffix in ('.json','.html','.md') and 'ledger_before' not in p.name:copy_changed(p,mirror/p.name)
    for p in (root/'jobs').glob('*/*'):
        if p.is_file() and p.suffix in ('.json','.st'):
            content=p.read_text(encoding='utf-8');assert s.sanitize(content)==content
            copy_changed(p,mirror/'jobs'/p.relative_to(root/'jobs'))
    if state.get('state')=='completed':
        (mirror/'最终报告.md').write_text(text,encoding='utf-8')
        with zipfile.ZipFile(mirror/'验收包.zip','w',zipfile.ZIP_DEFLATED) as archive:
            for p in mirror.rglob('*'):
                if p.is_file() and p.suffix!='.zip':archive.write(p,p.relative_to(mirror))
    return summary

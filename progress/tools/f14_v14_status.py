"""Four-arm latest-policy study: immutable twenty imported answers plus 120 new jobs."""
from collections import Counter
from html import escape
from pathlib import Path
import json
import zipfile
import f14_v14_core as s
from f14_v11_status import copy_changed

LABELS={'custom_deepseek-v4pro':'自研 DeepSeek','codex_deepseek-v4pro':'Codex DeepSeek','custom_minimax-m27':'自研 MiniMax','codex_minimax-m27':'Codex MiniMax'}

def record_for(root,job):
    return s.load(job['source_record'] if job.get('imported') else root/'jobs'/job['condition']/(job['pid']+'.json'))

def report(cfg,plan):
    root=Path(cfg['campaign_root']);mirror=s.MIRROR;mirror.mkdir(parents=True,exist_ok=True)
    ledger=s.load(cfg['budget_ledger_path']);state=s.load(root/'study_state.json');rows=[]
    for condition,label in LABELS.items():
        jobs=[j for j in plan['jobs']+plan['imported_jobs'] if j['condition']==condition]
        pairs=[(j,record_for(root,j)) for j in jobs];pairs=[(j,r) for j,r in pairs if r]
        records=[r for _,r in pairs];first=[r['attempts'][0] for r in records if r['attempts']]
        best=[r['attempts'][r['best_attempt']] for r in records if r.get('best_attempt') is not None]
        groups={}
        for name,prefix,total,cases in [('public','public-',20,470),('self_built','self-',15,476)]:
            selected=[r for j,r in pairs if j['pid'].startswith(prefix)]
            strongest=[r['attempts'][r['best_attempt']] for r in selected if r.get('best_attempt') is not None]
            groups[name]=dict(planned=total,completed=sum(r['job_done'] for r in selected),functional=sum(a['functional_pass'] for a in strongest),assertions_passed=sum(a['tests_passed'] for a in strongest),assertions_total=cases)
        statuses=Counter(a['verification_status'] for a in best if a.get('judge',{}).get('evidence_metadata',{}).get('stage')=='bounded')
        rows.append(dict(condition=condition,label=label,completed=sum(r['job_done'] for r in records),planned=35,
            first_functional=sum(a['functional_pass'] for a in first),final_functional=sum(a['functional_pass'] for a in best),
            native_passed=sum(a['native_pass'] for a in best),native_eligible=34,assertions_passed=sum(a['tests_passed'] for a in best),assertions_total=946,
            requests=sum(len(r['attempts']) for r in records),groups=groups,formal_statuses=dict(statuses),formal_not_executed=35-sum(statuses.values()),
            repair_gain=sum(not r['attempts'][0]['functional_pass'] and r['attempts'][r['best_attempt']]['functional_pass'] for r in records if r.get('best_attempt') is not None),
            accounted_cny=float(sum((s.money(a.get('cost_cny',0)) for r in records for a in r['attempts']),s.money(0)))))
    summary=dict(state=state,rows=rows,planned=140,completed=sum(r['completed'] for r in rows),imported_completed=20,new_planned=120,
        new_completed=sum(s.load(root/'jobs'/j['condition']/(j['pid']+'.json')).get('job_done',False) for j in plan['jobs']),
        new_requests=len(ledger['events'])-s.HISTORY,new_accounted_cny=float(s.money(ledger['spent_cny'])-s.money(s.BASELINE)),
        accounted_cny=ledger['spent_cny'],cap_cny=s.TOTAL,worst_cumulative_cny=plan['worst_cumulative_cny'],
        funding_sufficient=plan['funding_sufficient'],halt_reason=ledger.get('halted') if 'f14_v14_authorization' in ledger else '',updated_at=s.stamp())
    lines=['# 最新版35题四组对照（保留20题，补齐120题次）','',f"状态：{state.get('state')}；合计{summary['completed']}/140题次，新增{summary['new_completed']}/120。",'',
        '已完成的V13自研DeepSeek公共20题按原始文件绑定；不重复请求、不重复计费。其余120题使用字节一致的V13提示、反馈、裁判及相同模型参数。',
        '8题启动，完成4题后最多16题并行；每模型最多8请求，原生编译独占。每题最多4候选，输出24576。','',
        '| 组别 | 完成/35 | 功能首轮→最终/35 | 公共/20 | 自建/15 | 原生/34 | 用例/946 | 请求 |',
        '| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: |']
    for row in rows:lines.append(f"| {row['label']} | {row['completed']} | {row['first_functional']}→{row['final_functional']} | {row['groups']['public']['functional']} | {row['groups']['self_built']['functional']} | {row['native_passed']} | {row['assertions_passed']} | {row['requests']} |")
    lines+=['',f"项目累计计入{ledger['spent_cny']:.6f}元，上限{s.TOTAL}元；本批新增{summary['new_accounted_cny']:.6f}元。",
        f"完整最坏新增预留{plan['worst_reservation_cny']:.6f}元，最坏累计{plan['worst_cumulative_cny']:.6f}元。预留不是实际账单。",
        '预算状态：'+('可容纳完整计划' if plan['funding_sufficient'] else '超过当前已授权上限，尚未发送新付费请求'),'',
        '形式检查单列：'+json.dumps({r['label']:dict(statuses=r['formal_statuses'],not_executed=r['formal_not_executed']) for r in rows},ensure_ascii=False),
        '原VARIANT FIFO功能保留，原生分母34；未知费用、身份变化及公共工具错误时停止并保留现场，不自动补发。','更新：'+summary['updated_at']]
    text='\n'.join(lines)+'\n';s.atomic_json(root/'status.json',summary);(root/'实验状态.md').write_text(text,encoding='utf-8')
    (root/'status.html').write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta http-equiv="refresh" content="15"><title>140题次对照实验</title><style>body{font:16px/1.8 system-ui;max-width:1250px;margin:30px auto;padding:20px;background:#f3f6fb}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:white;padding:24px;border-radius:12px}</style><h1>最新版140题次对照实验</h1><pre>'+escape(text)+'</pre></html>',encoding='utf-8')
    for p in root.glob('*'):
        if p.is_file() and p.suffix in ('.json','.md','.html','.log') and 'ledger_before' not in p.name:copy_changed(p,mirror/p.name)
    for p in (root/'preparation_history').rglob('*.json'):
        copy_changed(p,mirror/'preparation_history'/p.relative_to(root/'preparation_history'))
    for job in plan['jobs']+plan['imported_jobs']:
        record=record_for(root,job)
        if not record:continue
        folder=Path(job['source_record']).parent if job.get('imported') else root/'jobs'/job['condition']
        target=mirror/('imported_v13' if job.get('imported') else 'jobs')/job['condition']
        for p in folder.glob(job['pid']+'.*'):
            if p.is_file() and p.suffix in ('.json','.st'):
                assert s.sanitize(p.read_text(encoding='utf-8'))==p.read_text(encoding='utf-8');copy_changed(p,target/p.name)
        for a in record['attempts']:
            native=a.get('judge',{}).get('platform_results',{}).get('codesys',{});artifact=native.get('artifact_dir')
            if artifact:
                for name in ('FB.st','source.st','result.json','compile_result.json','stdout.log','stderr.log'):
                    p=Path(artifact)/name
                    if p.exists():copy_changed(p,mirror/'native_evidence'/job['condition']/job['pid']/str(a['idx'])/name)
    if state.get('state')=='completed':
        (mirror/'最终报告.md').write_text(text,encoding='utf-8')
        with zipfile.ZipFile(mirror/'验收包.zip','w',zipfile.ZIP_DEFLATED) as archive:
            for p in mirror.rglob('*'):
                if p.is_file() and p.suffix!='.zip':archive.write(p,p.relative_to(mirror))
    return summary

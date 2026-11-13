"""Independent full-study status with public/self-built denominators and raw evidence."""
from collections import Counter
from html import escape
import json
from pathlib import Path
import shutil
import zipfile
from f14_v10_io import copyfile

LABELS={'custom_deepseek-v4pro':'自研 DeepSeek','codex_deepseek-v4pro':'Codex DeepSeek',
        'custom_minimax-m27':'自研 MiniMax','codex_minimax-m27':'Codex MiniMax'}
STATES={'prepared':'准备完成','running':'运行中','completed':'140题次完成','stopped':'已停止，保留现场'}

def report(cfg,plan):
    import f14_v10_core as s
    root=Path(cfg['campaign_root']);mirror=s.MIRROR;mirror.mkdir(parents=True,exist_ok=True)
    ledger=s.load(cfg['budget_ledger_path']);before=s.load(root/'ledger_before_study.json');rows=[]
    for condition,label in LABELS.items():
        records=[s.load(root/'jobs'/condition/(j['pid']+'.json')) for j in plan['jobs'] if j['condition']==condition]
        records=[r for r in records if r];first=[r['attempts'][0] for r in records if r['attempts']]
        best=[r['attempts'][r['best_attempt']] for r in records if r.get('best_attempt') is not None]
        events=[e for e in ledger['events'][s.HISTORY:] if e['request']['job_id'].startswith(condition+'/')]
        groups={}
        for name,public,total,cases in [('public',True,20,470),('self_built',False,15,476)]:
            group=[r for r in records if r['pid'].startswith('public-')==public]
            fa=[r['attempts'][0] for r in group if r['attempts']]
            ba=[r['attempts'][r['best_attempt']] for r in group if r.get('best_attempt') is not None]
            groups[name]=dict(planned=total,completed=sum(r['job_done'] for r in group),
                first_functional=sum(a['functional_pass'] for a in fa),final_functional=sum(a['functional_pass'] for a in ba),
                assertions_passed=sum(a['tests_passed'] for a in ba),assertions_total=cases,
                first_codesys=sum(a['native_pass'] for a in fa),final_codesys=sum(a['native_pass'] for a in ba),
                native_eligible=total-1 if public else total)
        rows.append(dict(condition=condition,label=label,recorded=sum(r['job_done'] for r in records),attempted=len(records),
            first_functional=sum(a['functional_pass'] for a in first),final_functional=sum(a['functional_pass'] for a in best),
            first_codesys=sum(a['native_pass'] for a in first),final_codesys=sum(a['native_pass'] for a in best),
            first_complete=sum(a['complete_code'] for a in first),final_complete=sum(a['complete_code'] for a in best),
            assertions_passed=sum(a['tests_passed'] for a in best),assertions_total=946,
            repair_gain=sum(not r['attempts'][0]['functional_pass'] and r['attempts'][r['best_attempt']]['functional_pass'] for r in records if r['attempts']),
            requests=len(events),formal_statuses=dict(Counter(a['verification_status'] for a in best)),
            seconds=sum(r.get('wall_seconds',0) for r in records),groups=groups,
            accounted_cny=float(sum((s.money(e.get('accounted_cny',e['reserved_cny'])) for e in events),s.money(0)))))
    state=s.load(root/'study_state.json')
    summary=dict(kind=s.KIND,state=state,rows=rows,planned=140,maximum_requests=560,maximum_candidates=4,
        recorded=sum(r['recorded'] for r in rows),requests=len(ledger['events'])-s.HISTORY,
        accounted_cny=ledger['spent_cny'],cap_cny=420,new_accounted_cny=float(s.money(ledger['spent_cny'])-s.money(s.BASELINE)),
        unsettled_reserved_cny=float(sum((s.money(e['reserved_cny']) for e in ledger['events'][s.HISTORY:] if e['status']=='reserved'),s.money(0))),
        original_events_preserved=s.prefix_ok(ledger,before),updated_at=s.stamp(),
        completion_audit_passed=s.load(root/'final_audit.json').get('passed',False))
    lines=['# Agent V10 全量独立验证','',STATES.get(state['state'],state['state']),
        f"已完成{summary['recorded']}/140题次，请求{summary['requests']}/560；累计计入{ledger['spent_cny']:.6f}/420元。",'',
        '35题（公共20、自建15）× 两模型 × 两框架，每题最多四候选。首次四题完成后增至八题并行，同模型最多四请求，原生编译独占。',
        '本轮全部重新生成；历史小试和免费复评独立存放。每组固定35题、946条功能用例；功能、原生编译与形式检查分别记录。','',
        '| 组别 | 完成/35 | CODESYS首次→最终/34 | 功能首次→最终/35 | 功能用例 | 修复新增成功 | 请求 |',
        '| --- | ---: | --- | --- | ---: | ---: | ---: |']
    for r in rows:lines.append(f"| {r['label']} | {r['recorded']} | {r['first_codesys']}→{r['final_codesys']} | {r['first_functional']}→{r['final_functional']} | {r['assertions_passed']}/946 | {r['repair_gain']} | {r['requests']} |")
    lines+=['','| 组别 | 公共题首次→最终/20 | 公共用例/470 | 自建题首次→最终/15 | 自建用例/476 |','| --- | --- | --- | --- | --- |']
    for r in rows:
        p=r['groups']['public'];own=r['groups']['self_built']
        lines.append(f"| {r['label']} | {p['first_functional']}→{p['final_functional']} | {p['assertions_passed']}/470 | {own['first_functional']}→{own['final_functional']} | {own['assertions_passed']}/476 |")
    lines+=['','| 组别 | 完整代码首次→最终/35 | 有界形式状态 | 本轮费用/元 |','| --- | --- | --- | ---: |']
    for r in rows:lines.append(f"| {r['label']} | {r['first_complete']}→{r['final_complete']} | {json.dumps(r['formal_statuses'],ensure_ascii=False)} | {r['accounted_cny']:.6f} |")
    lines+=['',f"本轮最坏预留{plan['worst_reservation_cny']:.6f}元；未结算预留{summary['unsettled_reserved_cny']:.6f}元。",
        '恢复说明：完整HTTP答卷在本地重放，不重发；已核验的超时请求保留费用上界，按调用失败记录。最终审计分别核对已结算及明确保留的超时预留，不将未知费用计为零。',
        '累计420元硬上限；沿用备用Key，80元不暂停。保留历史1266条费用事件与未知预留。',
        '通过即停止；仅明确的编译、功能或形式违反反馈触发修复。空正文、截断、重复候选不补发；身份、费用或公共工具异常时保存现场并停止新增请求。',
        'FIFO原VARIANT接口在冻结CODESYS平台单列不适用，原生编译分母为34；其功能评分仍保留在35题分母。',
        '运行中表格为当前记录；以“140题次完成”及最终审计通过为完成标志。完成后自动生成最终报告和验收包，并同步GitHub。',
        '', '最后更新：'+summary['updated_at'],'运行状态：'+json.dumps(state,ensure_ascii=False)]
    text='\n'.join(lines)+'\n';s.atomic_json(root/'status.json',summary);(root/'实验状态.md').write_text(text,encoding='utf-8')
    table=''.join('<tr><td>'+escape(r['label'])+'</td><td>'+str(r['recorded'])+'/35</td><td>'+str(r['groups']['public']['final_functional'])+'/20</td><td>'+str(r['groups']['self_built']['final_functional'])+'/15</td><td>'+str(r['assertions_passed'])+'/946</td></tr>' for r in rows)
    page='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="15"><title>V10全量独立验证</title><style>body{font:16px/1.7 system-ui,"Microsoft YaHei";max-width:1200px;margin:30px auto;padding:0 20px;background:#f3f6fb;color:#172b42}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:white;padding:24px;border-radius:12px}table{border-collapse:collapse;background:white;width:100%}td,th{text-align:left;padding:12px;border-bottom:1px solid #dce4ee}.hero{font-size:24px;font-weight:700}</style><h1>V10 全量独立验证</h1><p class="hero">'+escape(STATES.get(state['state'],state['state']))+' · '+str(summary['recorded'])+'/140</p><p>累计 '+f"{ledger['spent_cny']:.4f}"+' / 420 元 · 每15秒刷新</p><table><thead><tr><th>组别</th><th>已完成</th><th>公共题通过</th><th>自建题通过</th><th>功能用例</th></tr></thead><tbody>'+table+'</tbody></table><pre>'+escape(text)+'</pre></html>'
    (root/'status.html').write_text(page,encoding='utf-8')
    for name in ('study_plan.json','authorization_proof.json','offline_routes.json','offline_repair_routes.json','budget_refinement.json','validation.json','prepared.json','study_state.json','budget_authorization.json','run_environment.json','ledger_checkpoint.json','completion.json','final_audit.json','timeout_reservations.json','resume_ready.json','status.json','实验状态.md','status.html'):
        if (root/name).is_file():copyfile(root/name,mirror/name)
    for record_path in (root/'jobs').glob('*/*.json') if (root/'jobs').exists() else []:
        if record_path.name.count('.')!=1:continue
        record=s.load(record_path)
        if not record.get('job_done') and state['state']=='running':continue
        for file in record_path.parent.glob(record_path.stem+'.*'):
            if not file.is_file() or file.suffix=='.tmp':continue
            data=file.read_bytes();assert s.sanitize(data.decode('utf-8'))==data.decode('utf-8')
            target=mirror/'jobs'/file.relative_to(root/'jobs');target.parent.mkdir(parents=True,exist_ok=True);copyfile(file,target)
        # Native logs and submitted source are preserved with the candidate, without large project binaries.
        for attempt in record.get('attempts',[]):
            native=attempt.get('judge',{}).get('platform_results',{}).get('codesys',{});artifact=native.get('artifact_dir')
            if not artifact:continue
            for name in ('source.st','FB.st','compile_result.json','result.json','stdout.log','stderr.log'):
                file=Path(artifact)/name
                if not file.is_file():continue
                data=file.read_bytes();decoded=data.decode('utf-8',errors='replace');assert s.sanitize(decoded)==decoded
                target=mirror/'native_evidence'/record['condition']/record['pid']/str(attempt['idx'])/name
                target.parent.mkdir(parents=True,exist_ok=True);copyfile(file,target)
    if state['state']=='completed':
        (mirror/'最终报告.md').write_text(text,encoding='utf-8')
        with zipfile.ZipFile(mirror/'验收包.zip','w',zipfile.ZIP_DEFLATED) as archive:
            for file in sorted(mirror.rglob('*')):
                if file.is_file() and file.suffix!='.zip':archive.write(file,file.relative_to(mirror).as_posix())
    return summary

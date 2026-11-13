"""Public-only live results; incremental immutable-answer mirroring and explicit draining status."""
from collections import Counter
from html import escape
from pathlib import Path
import json
import shutil
import zipfile
from f14_v11_io import copyfile

LABELS={'custom_deepseek-v4pro':'自研 DeepSeek','codex_deepseek-v4pro':'Codex DeepSeek',
        'custom_minimax-m27':'自研 MiniMax','codex_minimax-m27':'Codex MiniMax'}
COPIED={}

def copy_changed(source,target):
    st=source.stat();key=str(source);signature=(st.st_size,st.st_mtime_ns)
    if COPIED.get(key)==signature and target.exists():return
    target.parent.mkdir(parents=True,exist_ok=True);copyfile(source,target);COPIED[key]=signature

def report(cfg,plan):
    import f14_v11_core as s
    root=Path(cfg['campaign_root']);mirror=s.MIRROR;mirror.mkdir(parents=True,exist_ok=True)
    ledger=s.load(cfg['budget_ledger_path']);before=s.load(root/'ledger_before_study.json');rows=[]
    events=ledger['events'][s.HISTORY:];state=s.load(root/'study_state.json')
    for condition,label in LABELS.items():
        records=[s.load(root/'jobs'/condition/(j['pid']+'.json')) for j in plan['jobs'] if j['condition']==condition]
        records=[r for r in records if r];first=[r['attempts'][0] for r in records if r['attempts']]
        best=[r['attempts'][r['best_attempt']] for r in records if r.get('best_attempt') is not None]
        fees=[e for e in events if e['request']['job_id'].startswith(condition+'/')]
        bounded=[a for a in best if a.get('judge',{}).get('evidence_metadata',{}).get('stage')=='bounded']
        rows.append(dict(condition=condition,label=label,recorded=sum(r['job_done'] for r in records),planned=20,
            first_functional=sum(a['functional_pass'] for a in first),final_functional=sum(a['functional_pass'] for a in best),
            first_codesys=sum(a['native_pass'] for a in first),final_codesys=sum(a['native_pass'] for a in best),
            first_complete=sum(a['complete_code'] for a in first),final_complete=sum(a['complete_code'] for a in best),
            assertions_passed=sum(a['tests_passed'] for a in best),assertions_total=470,
            repair_gain=sum(not r['attempts'][0]['functional_pass'] and r['attempts'][r['best_attempt']]['functional_pass'] for r in records if r['attempts']),
            requests=len(fees),formal_statuses=dict(Counter(a['verification_status'] for a in bounded)),formal_not_executed=20-len(bounded),
            accounted_cny=float(sum((s.money(e.get('accounted_cny',e['reserved_cny'])) for e in fees),s.money(0)))))
    halt=ledger.get('halted','') if 'f14_v11_authorization' in ledger else ''
    pending=[]
    for e in events:
        if e['status']!='reserved':continue
        condition,pid=e['request']['job_id'].split('/');idx=e['request']['candidate_index']
        diag=s.load(root/'transport_private'/condition/pid/str(idx)/'diagnostic.json')
        pending.append(dict(job_id=e['request']['job_id'],candidate=idx+1,status='已超时，保留费用预留' if diag.get('outcome')=='wall_deadline' else '等待模型返回',reserved_cny=e['reserved_cny']))
    labels={'prepared':'免费验收完成','running':'运行中','completed':'80题次完成','stopped':'已停止并保存现场'}
    display='停止新增请求，等待在途请求收尾' if halt and state['state']=='running' else labels.get(state['state'],state['state'])
    summary=dict(kind=s.KIND,state=state,display_state=display,halt_reason=halt,rows=rows,planned=80,
        recorded=sum(r['recorded'] for r in rows),requests=len(events),maximum_requests=320,
        accounted_cny=ledger['spent_cny'],cap_cny=420,new_accounted_cny=float(s.money(ledger['spent_cny'])-s.money(s.BASELINE)),
        unsettled_reserved_cny=float(sum((s.money(e['reserved_cny']) for e in events if e['status']=='reserved'),s.money(0))),
        pending_requests=pending,updated_at=s.stamp(),original_events_preserved=s.prefix_ok(ledger,before),
        completion_audit_passed=s.load(root/'final_audit.json').get('passed',False))
    lines=['# V11公共题独立验证','',display,
        f"完成{summary['recorded']}/80题次，请求{len(events)}/320；累计计入{ledger['spent_cny']:.6f}/420元。",'',
        '20道公共题 × 两模型 × 两框架；每题最多4候选，输出额度24576。初始8题次并行，4题完成后升至16；每模型最多8请求，CODESYS原生编译独占。',
        '改进：控制结构检查、按编译进展选取修复候选、历史错误记忆、包含之前实际输出的完整公开输入轨迹。原题、隐藏期望、规约及评分解释器保持冻结。','',
        '| 组别 | 完成/20 | 功能首次→最终/20 | 原生编译首次→最终/19 | 用例通过/470 | 修复新增 | 请求 | 本轮计入/元 |',
        '| --- | ---: | --- | --- | ---: | ---: | ---: | ---: |']
    for r in rows:lines.append(f"| {r['label']} | {r['recorded']} | {r['first_functional']}→{r['final_functional']} | {r['first_codesys']}→{r['final_codesys']} | {r['assertions_passed']} | {r['repair_gain']} | {r['requests']} | {r['accounted_cny']:.6f} |")
    lines+=['','| 组别 | 实际进入形式阶段的最终候选状态 | 未执行形式阶段 |','| --- | --- | ---: |']
    for r in rows:lines.append(f"| {r['label']} | {json.dumps(r['formal_statuses'],ensure_ascii=False)} | {r['formal_not_executed']} |")
    lines+=['',f"本轮完整最坏预留{plan['worst_reservation_cny']:.6f}元。历史费用及未知预留保持，使用原备用Key；80元不暂停，420元为累计硬上限。",
        '原FIFO的VARIANT接口在当前原生平台单列，因此原生分母19；功能分母20保持。首候选全部重新生成，V10答卷与成绩独立保留。',
        '请求超时或费用不明时，停止新增请求、保存全部记录；本地文件访问重试不会重发模型请求。',
        '费用包含已结算的配置价格估算与未确认费用预留。通过是功能整题通过，形式通过另指有界检查通过。',
        '', '在途/未结算请求：'+json.dumps(pending,ensure_ascii=False),'停止原因：'+halt,'更新：'+summary['updated_at']]
    text='\n'.join(lines)+'\n';s.atomic_json(root/'status.json',summary);(root/'实验状态.md').write_text(text,encoding='utf-8')
    html='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="15"><title>V11公共题验证</title><style>body{font:16px/1.8 system-ui,"Microsoft YaHei";max-width:1200px;margin:30px auto;padding:0 20px;background:#f3f6fb;color:#172b42}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:white;padding:24px;border-radius:12px}</style><h1>V11 公共题独立验证</h1><p>'+escape(display)+' · '+str(summary['recorded'])+'/80</p><p>输出24576 token · 最多16题次并行 · 每15秒刷新</p><pre>'+escape(text)+'</pre></html>'
    (root/'status.html').write_text(html,encoding='utf-8')
    for name in ('study_plan.json','authorization_proof.json','offline_routes.json','offline_repair_routes.json','budget_refinement.json','validation.json','prepared.json','study_state.json','budget_authorization.json','run_environment.json','ledger_checkpoint.json','completion.json','final_audit.json','status.json','实验状态.md','status.html'):
        if (root/name).exists():copy_changed(root/name,mirror/name)
    for p in (root/'jobs').glob('*/*.json') if (root/'jobs').exists() else []:
        if p.name.count('.')!=1:continue
        record=s.load(p)
        if not record.get('job_done') and state['state']=='running':continue
        for file in p.parent.glob(p.stem+'.*'):
            if not file.is_file() or file.suffix=='.tmp':continue
            content=file.read_bytes().decode('utf-8');assert s.sanitize(content)==content
            copy_changed(file,mirror/'jobs'/file.relative_to(root/'jobs'))
        for a in record.get('attempts',[]):
            native=a.get('judge',{}).get('platform_results',{}).get('codesys',{});artifact=native.get('artifact_dir')
            if not artifact:continue
            for name in ('FB.st','source.st','result.json','compile_result.json','stdout.log','stderr.log'):
                file=Path(artifact)/name
                if file.exists():copy_changed(file,mirror/'native_evidence'/record['condition']/record['pid']/str(a['idx'])/name)
    if state['state']=='completed':
        (mirror/'最终报告.md').write_text(text,encoding='utf-8')
        with zipfile.ZipFile(mirror/'验收包.zip','w',zipfile.ZIP_DEFLATED) as archive:
            for file in sorted(mirror.rglob('*')):
                if file.is_file() and file.suffix!='.zip':archive.write(file,file.relative_to(mirror).as_posix())
    return summary

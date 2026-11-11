"""Status artifacts and loopback-only viewer for the independent F1.4 batch."""
from collections import Counter
from html import escape
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import json
from pathlib import Path
import shutil
import zipfile

LABELS={'custom_deepseek-v4pro':'自研 DeepSeek','codex_deepseek-v4pro':'Codex DeepSeek',
        'custom_minimax-m27':'自研 MiniMax','codex_minimax-m27':'Codex MiniMax'}
STATES={'prepared':'准备完成，尚未调用模型','running':'实验运行中','completed':'140题次完成',
        'paused_for_api_review':'已到80元检查点，等待人工检查','stopped':'已停止，需检查现场'}

def report(cfg,plan):
    import f14_study as s
    root=Path(cfg['campaign_root']);mirror=s.MIRROR;mirror.mkdir(parents=True,exist_ok=True)
    ledger=s.load(cfg['budget_ledger_path']);before=s.load(root/'ledger_before_study.json');rows=[]
    for condition,label in LABELS.items():
        records=[s.load(root/'jobs'/condition/(j['pid']+'.json')) for j in plan['jobs'] if j['condition']==condition]
        records=[r for r in records if r];first=[r['attempts'][0] for r in records if r['attempts']]
        best=[r['attempts'][r['best_attempt']] for r in records if r.get('best_attempt') is not None]
        rows.append(dict(condition=condition,label=label,recorded=sum(bool(r['job_done']) for r in records),
            attempted=len(records),first_functional=sum(a['functional_pass'] for a in first),final_functional=sum(a['functional_pass'] for a in best),
            first_codesys=sum(a['native_pass'] for a in first),final_codesys=sum(a['native_pass'] for a in best),
            first_complete=sum(a['complete_code'] for a in first),final_complete=sum(a['complete_code'] for a in best),
            assertions_passed=sum(a['tests_passed'] for a in best),assertions_total=946,
            repair_gain=sum(not r['attempts'][0]['functional_pass'] and r['attempts'][r['best_attempt']]['functional_pass'] for r in records if r['attempts']),
            requests=sum(e.get('request',{}).get('job_id','').startswith(condition+'/') for e in ledger['events'][s.HISTORY:]),
            formal_statuses=dict(Counter(a['verification_status'] for a in best)),
            seconds=sum(r.get('wall_seconds',0) for r in records),
            settled_cost_cny=float(sum((s.money(e.get('accounted_cny',0)) for e in ledger['events'][s.HISTORY:]
                if e.get('request',{}).get('job_id','').startswith(condition+'/')),s.money(0)))))
    state=s.load(root/'study_state.json');summary=dict(kind=s.KIND,state=state,rows=rows,
        planned=140,recorded=sum(r['recorded'] for r in rows),attempted=sum(r['attempted'] for r in rows),
        requests=len(ledger['events'])-s.HISTORY,accounted_cny=ledger['spent_cny'],cap_cny=190,checkpoint_cny=80,
        new_accounted_cny=float(s.money(ledger['spent_cny'])-s.money(s.BASELINE)),
        new_unknown_reserved_cny=sum(e['reserved_cny'] for e in ledger['events'][s.HISTORY:] if e['status']=='reserved'),
        original_events_preserved=s.prefix_ok(ledger,before),updated_at=s.stamp())
    lines=['# F1.4-P1独立35题四组实验','',STATES.get(state['state'],state['state']),
        f"归档{summary['recorded']}/140题次，模型请求{summary['requests']}/280；累计计入{ledger['spent_cny']:.6f}/190元，80元检查点。",'',
        '每组35题、946条功能用例。CODESYS原生可评价34题；FIFO原VARIANT按平台不支持单列，功能及形式仍按原型，DINT变体不混入。',
        '功能测试由Python扫描解释器执行；形式有界通过不等于完整证明。Codex为真实CLI受控基线，外层统一反馈。','',
        '| 组别 | 已归档 | 编译首次→最终/34 | 功能首次→最终/35 | 最终断言/946 | 修复新增 | 请求 |',
        '| --- | ---: | --- | --- | ---: | ---: | ---: |']
    for r in rows:
        lines.append(f"| {r['label']} | {r['recorded']}/35 | {r['first_codesys']}→{r['final_codesys']} | {r['first_functional']}→{r['final_functional']} | {r['assertions_passed']} | {r['repair_gain']} | {r['requests']} |")
    lines+=['','| 组别 | 完整代码首次→最终/35 | 最终形式状态 | 已结算估算/元 | 题次耗时/秒 |','| --- | --- | --- | ---: | ---: |']
    for r in rows:lines.append(f"| {r['label']} | {r['first_complete']}→{r['final_complete']} | {json.dumps(r['formal_statuses'],ensure_ascii=False)} | {r['settled_cost_cny']:.6f} | {r['seconds']:.1f} |")
    lines+=['',f"本轮最坏预留{plan['worst_reservation_cny']:.6f}元；新增未知预留{summary['new_unknown_reserved_cny']:.6f}元。历史未知预留保留；计入金额不是供应商实际账单。",
        '空正文、截断不自动补发；身份不符、未知费用或公共工具故障停止。80元暂停后不会自动继续；换API须另立批次。',
        '正式原参考32/35编译通过；两份独立参考兼容补丁不改题面、接口、测试，不自动改写模型候选。',
        '新版结果与旧review-r8批次独立，不拼接成绩。', '', '最近状态：'+json.dumps(state,ensure_ascii=False)]
    text='\n'.join(lines)+'\n'
    s.atomic_json(root/'status.json',summary);(root/'实验状态.md').write_text(text,encoding='utf-8')
    page='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="15"><title>F1.4-P1实验状态</title><style>body{font:16px/1.7 system-ui,"Microsoft YaHei";max-width:1200px;margin:30px auto;padding:0 20px;background:#f3f6fb;color:#172b42}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:white;padding:24px;border-radius:12px;border:1px solid #d9e1ec}</style><h1>F1.4-P1实验状态</h1><p>每15秒刷新。接近累计80元自动暂停。</p><pre>'+escape(text)+'</pre></html>'
    (root/'status.html').write_text(page,encoding='utf-8')
    for name in ('study_plan.json','validation.json','prepared.json','study_state.json','budget_authorization.json','run_environment.json','ledger_checkpoint.json','completion.json','final_audit.json','status.json','实验状态.md','status.html'):
        if (root/name).is_file():shutil.copyfile(root/name,mirror/name)
    for file in (root/'jobs').rglob('*') if (root/'jobs').exists() else []:
        if file.is_file():
            data=file.read_bytes();assert s.sanitize(data.decode('utf-8'))==data.decode('utf-8')
            target=mirror/'jobs'/file.relative_to(root/'jobs');target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(file,target)
    if state['state']=='completed':
        (mirror/'最终报告.md').write_text(text,encoding='utf-8')
        with zipfile.ZipFile(mirror/'验收包.zip','w',zipfile.ZIP_DEFLATED) as archive:
            for file in sorted(mirror.rglob('*')):
                if file.is_file() and file.suffix!='.zip':archive.write(file,file.relative_to(mirror).as_posix())
    return summary

def serve(cfg,port):
    root=Path(cfg['campaign_root'])
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            name=self.path.split('?',1)[0].lstrip('/') or 'status.html'
            if name not in ('status.html','status.json') or not (root/name).is_file():self.send_error(404);return
            data=(root/name).read_bytes();self.send_response(200)
            self.send_header('Content-Type','text/html; charset=utf-8' if name.endswith('.html') else 'application/json; charset=utf-8')
            self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
        def log_message(self,*args):pass
    ThreadingHTTPServer(('127.0.0.1',port),Handler).serve_forever()

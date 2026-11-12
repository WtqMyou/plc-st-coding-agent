"""Public-task pilot status, raw evidence mirroring and request-level audit."""
from collections import Counter
from html import escape
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import json
from pathlib import Path
import shutil
import zipfile
LABELS={'custom_deepseek-v4pro':'自研 DeepSeek','codex_deepseek-v4pro':'Codex DeepSeek',
        'custom_minimax-m27':'自研 MiniMax','codex_minimax-m27':'Codex MiniMax'}
STATES={'prepared':'准备完成','running':'运行中','completed':'24题次完成','stopped':'已停止，保留现场'}

def report(cfg,plan):
    import f14_v6_core as s
    root=Path(cfg['campaign_root']);mirror=s.MIRROR;mirror.mkdir(parents=True,exist_ok=True)
    ledger=s.load(cfg['budget_ledger_path']);before=s.load(root/'ledger_before_study.json');rows=[]
    cases=sum(len(p['test_cases']) for p in s.tasks().values())
    for condition,label in LABELS.items():
        records=[s.load(root/'jobs'/condition/(j['pid']+'.json')) for j in plan['jobs'] if j['condition']==condition]
        records=[r for r in records if r]
        first=[r['attempts'][0] for r in records if r['attempts']]
        best=[r['attempts'][r['best_attempt']] for r in records if r.get('best_attempt') is not None]
        events=[e for e in ledger['events'][s.HISTORY:] if e['request']['job_id'].startswith(condition+'/')]
        rows.append(dict(condition=condition,label=label,recorded=sum(bool(r['job_done']) for r in records),
            attempted=len(records),first_functional=sum(a['functional_pass'] for a in first),final_functional=sum(a['functional_pass'] for a in best),
            first_codesys=sum(a['native_pass'] for a in first),final_codesys=sum(a['native_pass'] for a in best),
            first_complete=sum(a['complete_code'] for a in first),final_complete=sum(a['complete_code'] for a in best),
            assertions_passed=sum(a['tests_passed'] for a in best),assertions_total=cases,
            repair_gain=sum(not r['attempts'][0]['functional_pass'] and r['attempts'][r['best_attempt']]['functional_pass'] for r in records if r['attempts']),
            contract_rules_checked=sum(a.get('judge',{}).get('evidence_metadata',{}).get('declared_contract_check',{}).get('supported',0) for a in best),
            contract_rule_violations=sum(len(a.get('judge',{}).get('evidence_metadata',{}).get('declared_contract_check',{}).get('violations',[])) for a in best),
            contract_present=sum(a.get('engineering_contract',{}).get('present',False) for a in best),
            requests=len(events),formal_statuses=dict(Counter(a['verification_status'] for a in best)),
            seconds=sum(r.get('wall_seconds',0) for r in records),
            accounted_cny=float(sum((s.money(e.get('accounted_cny',e['reserved_cny'])) for e in events),s.money(0)))))
    state=s.load(root/'study_state.json')
    summary=dict(kind=s.KIND,state=state,rows=rows,planned=24,recorded=sum(r['recorded'] for r in rows),
        requests=len(ledger['events'])-s.HISTORY,accounted_cny=ledger['spent_cny'],cap_cny=210,
        new_accounted_cny=float(s.money(ledger['spent_cny'])-s.money(s.BASELINE)),
        unsettled_reserved_cny=float(sum((s.money(e['reserved_cny']) for e in ledger['events'][s.HISTORY:] if e['status']=='reserved'),s.money(0))),
        original_events_preserved=s.prefix_ok(ledger,before),updated_at=s.stamp())
    lines=['# Agent V6公共题多轮修复小试','',STATES.get(state['state'],state['state']),
        f"已完成{summary['recorded']}/24题次，请求{summary['requests']}/96；累计计入{ledger['spent_cny']:.6f}/210元。",'',
        '六道公共题 × 两模型 × 两框架，每题最多四候选、至多三次修复。4题次并行、同模型最多2请求，原生编译独占。',
        '改进：结构体/数组值复制、CODESYS字节类型与转换、完整公开输入轨迹、自声明规则执行核对、最多四候选修复。原题、参考程序、测试期望和规约均保持原版。',
        '生成与修复提示不含参考答案、测试期望值或私有规约观察器；输入轨迹及实际输出属于执行反馈。','',
        '| 组别 | 完成/6 | CODESYS首次→最终/6 | 功能首次→最终/6 | 用例通过 | 修复新增 | 请求 | 工程表/6 | 自声明规则检查/违例 |',
        '| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | --- |']
    for r in rows:
        lines.append(f"| {r['label']} | {r['recorded']} | {r['first_codesys']}→{r['final_codesys']} | {r['first_functional']}→{r['final_functional']} | {r['assertions_passed']}/{cases} | {r['repair_gain']} | {r['requests']} | {r['contract_present']} | {r['contract_rules_checked']}/{r['contract_rule_violations']} |")
    lines+=['','| 组别 | 完整代码首次→最终 | 形式状态 | 本轮计入/元 |','| --- | --- | --- | ---: |']
    for r in rows:lines.append(f"| {r['label']} | {r['first_complete']}→{r['final_complete']} | {json.dumps(r['formal_statuses'],ensure_ascii=False)} | {r['accounted_cny']:.6f} |")
    lines+=['',f"本轮最坏预留{plan['worst_reservation_cny']:.6f}元；本轮未结算预留{summary['unsettled_reserved_cny']:.6f}元。",
        '费用含已结算估算及未确认预留，保留全部历史未知费用。继续使用备用Key，80元不暂停，210元为累计硬上限。',
        '空正文、截断、调用错误不自动重发。身份不符、未知费用或公共工具故障停止并保留现场。',
        '本轮为六题诊断，结果独立保留；功能、原生编译及有界形式状态分别统计。自声明契约检查只核对候选声明与实现是否一致，不代替题面正确性或改变评分。','',
        '题目：'+', '.join(s.tasks()),'', '最近状态：'+json.dumps(state,ensure_ascii=False)]
    text='\n'.join(lines)+'\n'
    s.atomic_json(root/'status.json',summary);(root/'实验状态.md').write_text(text,encoding='utf-8')
    page='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="15"><title>V6公共题改进小试</title><style>body{font:16px/1.7 system-ui,"Microsoft YaHei";max-width:1200px;margin:30px auto;padding:0 20px;background:#f3f6fb;color:#172b42}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:white;padding:24px;border-radius:12px}</style><h1>V6公共题改进小试</h1><p>每15秒刷新；累计210元上限。</p><pre>'+escape(text)+'</pre></html>'
    (root/'status.html').write_text(page,encoding='utf-8')
    for name in ('study_plan.json','authorization_proof.json','offline_routes.json','validation.json','prepared.json','study_state.json','budget_authorization.json','run_environment.json','ledger_checkpoint.json','completion.json','final_audit.json','status.json','实验状态.md','status.html'):
        if (root/name).is_file():shutil.copyfile(root/name,mirror/name)
    for record_path in (root/'jobs').glob('*/*.json') if (root/'jobs').exists() else []:
        if record_path.name.count('.')!=1:continue
        record=s.load(record_path)
        if not record.get('job_done') and state['state']=='running':continue
        for file in record_path.parent.glob(record_path.stem+'.*'):
            if not file.is_file() or file.suffix=='.tmp':continue
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

def audit_final(cfg,plan):
    import f14_v6_core as s
    root=Path(cfg['campaign_root']);state=s.load(cfg['budget_ledger_path'])
    events=state['events'][s.HISTORY:]
    linked={(e['request']['job_id'],e['request']['candidate_index']):e for e in events}
    assert len(linked)==len(events)<=96 and s.prefix_ok(state,s.load(root/'ledger_before_study.json'))
    requests=0
    for job in plan['jobs']:
        folder=root/'jobs'/job['condition'];record=s.load(folder/(job['pid']+'.json'))
        assert record['job_done'] and record['best_attempt']==s.select_best(record['attempts'])
        assert len(record['attempts']) in (1,2,3,4)
        for index,a in enumerate(record['attempts']):
            event=linked[(job['job_id'],index)];assert event['status']=='settled'
            assert s.money(event['accounted_cny'])==s.money(a['cost_cny'])
            assert a['actual_model']==event['metadata']['model']
            for field in ('prompt_tokens','completion_tokens'):assert a[field]==event['metadata'][field]
            assert (folder/(job['pid']+f'.request_{index+1:02}.json')).is_file()
            assert (folder/(job['pid']+f'.response_{index+1:02}.json')).is_file()
            if a['code']:
                raw=(folder/(job['pid']+f'.raw_candidate_{index+1:02}.st')).read_bytes().decode()
                normalized,edits=s.normalize(raw)
                assert normalized==a['code'] and edits==a['format_edits']
                assert (folder/(job['pid']+f'.candidate_{index+1:02}.st')).read_bytes()==normalized.encode()
                assert s.hashlib.sha256(normalized.encode()).hexdigest()==a['code_hash']
            requests+=1
    assert requests==len(events)
    return dict(passed=True,jobs=24,requests=requests,cases_per_arm=sum(len(p['test_cases']) for p in s.tasks().values()),normalization_reproducible=True,
        original_events_preserved=True,all_new_requests_settled=True,accounted_cny=state['spent_cny'],ledger_sha256=s.sha(cfg['budget_ledger_path']))

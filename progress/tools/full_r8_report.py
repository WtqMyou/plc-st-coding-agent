"""Read-only dashboard and reproducible final audit for the full reviewed study."""
from collections import Counter
from datetime import datetime
from html import escape
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import hashlib
import json
from pathlib import Path
import zipfile
import full_r8_study as s

LABELS={'custom_deepseek-v4pro':'自研 DeepSeek','codex_deepseek-v4pro':'Codex DeepSeek',
        'custom_minimax-m27':'自研 MiniMax','codex_minimax-m27':'Codex MiniMax'}
STATES={'prepared':'免费预检完成，尚未调用模型','running':'实验运行中','completed':'全部140题次完成',
        'paused_for_api_review':'已暂停，等待你检查费用与API','stopped':'实验已停止，需要检查'}

def metrics(cfg,plan):
    root=Path(cfg['campaign_root']);rows=[]
    for condition,label in LABELS.items():
        records=[s.load(root/'jobs'/condition/(j['pid']+'.json')) for j in plan['jobs'] if j['condition']==condition]
        first=[r.get('attempts',[{}])[0] if r.get('attempts') else {} for r in records]
        best=[next((a for a in r.get('attempts',[]) if a['idx']==r.get('best_attempt')),{}) for r in records]
        attempts=[a for r in records for a in r.get('attempts',[])]
        row=dict(condition=condition,label=label,planned=35,recorded=sum(bool(r.get('job_done')) for r in records),
                 attempted=sum(bool(r.get('attempts')) for r in records),requests=len(attempts),
                 first_solved=sum(bool(r.get('first_try')) for r in records),solved=sum(bool(r.get('solved')) for r in records),
                 repair_gain=sum(bool(r.get('solved') and not r.get('first_try')) for r in records),
                 two_candidates=sum(len(r.get('attempts',[]))==2 for r in records),
                 complete_code=sum(bool(r.get('complete_code')) for r in records),
                 first_codesys=sum(a.get('platform_results',{}).get('codesys',{}).get('status')=='passed' for a in first),
                 final_codesys=sum(a.get('platform_results',{}).get('codesys',{}).get('status')=='passed' for a in best),
                 first_tests_passed=sum(a.get('tests_passed',0) for a in first),
                 tests_passed=sum(a.get('tests_passed',0) for a in best),tests_total=1214,
                 confirmed_cost_cny=float(sum((s.money(a.get('cost_cny',0)) for a in attempts),s.money(0))),
                 tokens=sum(a.get('prompt_tokens',0)+a.get('completion_tokens',0) for a in attempts),
                 wall_seconds=round(sum(s.load(root/'jobs'/condition/(j['pid']+'.timing.json')).get('wall_seconds',0)
                                for j in plan['jobs'] if j['condition']==condition),3),
                 formal_statuses=dict(Counter(a.get('verification_status','not_run') for a in best)),
                 formal_attempts=sum(bool(a.get('judge',{}).get('model_check',{}).get('executed')) for a in attempts),
                 generation_incomplete=sum(bool(a.get('provider_error','').startswith('Generation incomplete/empty:')) for a in attempts),
                 unsupported_modeling=sum(a.get('judge',{}).get('evidence_metadata',{}).get('classification')=='unsupported_modeling' for a in best))
        rows.append(row)
    ledger=s.load(cfg['budget_ledger_path']);before=s.load(root/'ledger_before_study.json')
    return dict(kind=s.KIND,state=s.load(root/'study_state.json').get('state','prepared'),rows=rows,
                planned=140,recorded=sum(r['recorded'] for r in rows),actual_requests=sum(r['requests'] for r in rows),
                new_events=len(ledger['events'])-s.HISTORY,
                study_increment_cny=float(s.money(ledger['spent_cny'])-s.money(s.BASELINE)),
                total_accounted_cny=ledger['spent_cny'],total_cap_cny=170,initial_review_checkpoint_cny=80,
                current_review_checkpoint_cny=s.load(root/'review_authorization.json').get('review_ceiling_cny',80),
                historical_unknown_reserved_cny=sum(e['reserved_cny'] for e in before['events'] if e['status']=='reserved'),
                new_unknown_reserved_cny=sum(e['reserved_cny'] for e in ledger['events'][s.HISTORY:] if e['status']=='reserved'),
                all_original_events_preserved=s.prefix_ok(ledger,before),halted=ledger.get('halted'),updated_at=s.stamp())

def markdown(cfg,plan,summary):
    state=s.load(Path(cfg['campaign_root'])/'study_state.json')
    lines=['# 最新版本35题四组实验状态','',STATES.get(summary['state'],summary['state'])+f"；归档{summary['recorded']}/140题次。",
           '每组35题1214功能断言；两次候选上限，失败保留分母。首次→最终统计使用冻结的候选选择规则。','',
           '| 组别 | 归档 | CODESYS首次→最终 | 功能首次→最终 | 最终断言 | 修复新增 | 请求 | 已确认费用/元 |',
           '| --- | ---: | --- | --- | ---: | ---: | ---: | ---: |']
    for r in summary['rows']:
        lines.append(f"| {r['label']} | {r['recorded']}/35 | {r['first_codesys']}→{r['final_codesys']}/35 | {r['first_solved']}→{r['solved']}/35 | {r['tests_passed']}/1214 | {r['repair_gain']} | {r['requests']} | {r['confirmed_cost_cny']:.6f} |")
    lines+=['',f"本轮计入{summary['study_increment_cny']:.6f}元；累计{summary['total_accounted_cny']:.6f}/170元。当前人工检查点{summary['current_review_checkpoint_cny']}元。",
            f"最坏完整预留{plan['worst_reservation_cny']:.6f}元；新增未知预留{summary['new_unknown_reserved_cny']:.6f}元，历史未知预留继续保留。",
            '费用为配置单价及预留计入，不是供应商账单。接近检查点暂停，不自动越过；更换API须另立批次。','',
            '| 组别 | 形式状态（最终候选） | 实际形式检查次数 | 题次耗时/秒 |',
            '| --- | --- | ---: | ---: |']
    for r in summary['rows']:
        lines.append(f"| {r['label']} | {json.dumps(r['formal_statuses'],ensure_ascii=False)} | {r['formal_attempts']} | {r['wall_seconds']:.1f} |")
    lines+=['','形式违反、截断、超时、未决及未执行分别保留；有界通过不等于完整形式证明。CODESYS是真实编译，功能由扫描语义解释器测试，不声称物理PLC运行。',
            'Codex为真实CLI受控代码生成基线，外层裁判统一提供反馈；不代表无限制Codex自主工具能力。']
    if state.get('current_job'):lines+=['','当前题次：'+state['current_job']]
    if state.get('next_job'):lines+=['','待接续题次：'+state['next_job']]
    if state.get('reason') or state.get('error'):lines+=['','暂停/停止原因：'+state.get('reason',state.get('error',''))]
    return '\n'.join(lines)+'\n'

def html(cfg,plan,summary):
    text=markdown(cfg,plan,summary)
    return ('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            '<meta http-equiv="refresh" content="15"><title>35题四组正式实验</title>'
            '<style>body{margin:0;background:#f2f5fa;color:#24334a;font:16px/1.8 system-ui,"Microsoft YaHei",sans-serif}main{max-width:1250px;margin:auto;padding:28px 20px}'
            'section{background:white;border:1px solid #dae2ed;border-radius:12px;padding:22px;margin:18px 0;overflow:auto}table{border-collapse:collapse;width:100%;white-space:nowrap}'
            'td,th{border-bottom:1px solid #dde4ef;text-align:left;padding:10px}a{color:#175eac}pre{white-space:pre-wrap;overflow-wrap:anywhere}</style><main>'
            '<h1>35题四组正式实验</h1><section><h2>'+escape(STATES.get(summary['state'],summary['state']))+'</h2>'
            f"<p>已归档 <b>{summary['recorded']}/140</b>；请求 {summary['actual_requests']}/280。</p>"
            f"<p>累计计入 <b>¥{summary['total_accounted_cny']:.6f}</b>；人工检查点 <b>¥{summary['current_review_checkpoint_cny']}</b>；总上限 ¥170。</p>"
            '</section><section><table><tr><th>组别</th><th>归档</th><th>CODESYS首次→最终</th><th>功能首次→最终</th><th>最终断言</th><th>修复新增</th><th>费用/元</th></tr>'+
            ''.join(f"<tr><td>{r['label']}</td><td>{r['recorded']}/35</td><td>{r['first_codesys']}→{r['final_codesys']}/35</td><td>{r['first_solved']}→{r['solved']}/35</td><td>{r['tests_passed']}/1214</td><td>{r['repair_gain']}</td><td>{r['confirmed_cost_cny']:.6f}</td></tr>" for r in summary['rows'])+
            '</table></section><section><h2>记录与边界</h2><pre>'+escape(text)+'</pre><p>'
            '<a href="https://github.com/WtqMyou/plc-st-coding-agent/tree/main/progress/evidence/full_r8_20261110">GitHub完整记录</a>'
            ' · <a href="/最终报告.md">最终报告</a> · <a href="/验收包.zip">验收包</a></p></section></main></html>')

def public_files(root):
    names={'study_plan.json','prepared.json','validation.json','native_preflight.json','offline_routes.json',
           'study_state.json','study_summary.json','budget_authorization.json','review_authorization.json',
           'run_environment.json','completion.json','ledger_checkpoint.json','billing_audit.json','analysis.json',
           'release_manifest.json','package_manifest.json','实验状态.md','最终报告.md','状态.html','验收包.zip'}
    return [p for p in root.rglob('*') if p.is_file() and
            (p.name in names or any(x in ('jobs','frozen_requests','native_evidence') for x in p.relative_to(root).parts))]

def mirror(root):
    s.MIRROR.mkdir(parents=True,exist_ok=True)
    for p in public_files(root):
        target=s.MIRROR/p.relative_to(root);target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(p.read_bytes())

def report(cfg,plan):
    root=Path(cfg['campaign_root']);summary=metrics(cfg,plan)
    s.atomic_json(root/'study_summary.json',summary)
    (root/'实验状态.md').write_bytes(markdown(cfg,plan,summary).encode())
    (root/'状态.html').write_bytes(html(cfg,plan,summary).encode())
    ledger=s.load(cfg['budget_ledger_path'])
    s.atomic_json(root/'billing_audit.json',dict(initial_ledger_sha256=plan['initial_ledger_sha256'],
                  original_events_preserved=summary['all_original_events_preserved'],
                  original_event_count=450,events=ledger['events'][450:],study_increment_cny=summary['study_increment_cny'],
                  total_accounted_cny=summary['total_accounted_cny'],authorization=ledger.get('full_r8_authorization')))
    mirror(root)
    return summary

def audit_final(cfg,plan,released=False):
    root=Path(cfg['campaign_root']);s.verify(root)
    assert s.load(root/'study_state.json')['state']=='completed','Study incomplete'
    ledger=s.history(cfg,root,plan)
    assert ledger['limit_cny']==170 and not ledger['halted']
    events=ledger['events'][450:];by_key={(e['request']['job_id'],e['request']['candidate_index']):e for e in events}
    assert len(events)<=280 and all(e['status']=='settled' for e in events)
    assert len(list((root/'jobs').rglob('*.request_*.json')))==len(events)
    assert len(list((root/'jobs').rglob('*.response_*.json')))==len(events)
    details=[];total=s.money(0)
    for job in plan['jobs']:
        folder=root/'jobs'/job['condition'];r=s.load(folder/(job['pid']+'.json'));timing=s.load(folder/(job['pid']+'.timing.json'))
        assert r['job_done'] and 1<=len(r['attempts'])<=2 and timing['upstream_requests_entered']==len(r['attempts'])
        assert r['study_plan_sha256']==s.sha(root/'study_plan.json')
        model=next(m for m in cfg['models'] if m['id']==job['model_id'])
        assert timing['wall_seconds']<=1200
        for idx,a in enumerate(r['attempts']):
            event=by_key[(job['job_id'],idx)]
            request=s.load(folder/(job['pid']+f'.request_{idx+1:02}.json'))
            response=s.load(folder/(job['pid']+f'.response_{idx+1:02}.json'))
            assert request['model']==model['model']==event['request']['model']
            assert request['parameters']==model['parameters'] and request['max_tokens']==16384
            assert response['model']==a['actual_model']==event['metadata']['model']
            assert response['model'].casefold() in {x.casefold() for x in model['accepted_models']}
            assert response['usage']==event['metadata']['usage']
            assert a['prompt_tokens']==event['metadata']['prompt_tokens'] and a['completion_tokens']==event['metadata']['completion_tokens']
            fee=s.money((a['prompt_tokens']*model['input_cny_per_million']+a['completion_tokens']*model['output_cny_per_million'])/1e6)
            assert fee==s.money(a['cost_cny'])==s.money(event['accounted_cny']);total+=fee
            upper=s.money(((len(json.dumps(request['messages'],ensure_ascii=False).encode())+4096)*model['input_cny_per_million']+16384*model['output_cny_per_million'])/1e6)
            assert upper==s.money(event['reserved_cny'])<=s.money(job['first_upper_cny'] if idx==0 else job['repair_upper_cny'])
            if a['code']:
                assert s.extract_code(response['message'].get('content',''))==a['code']
                assert hashlib.sha256(a['code'].encode()).hexdigest()==a['code_hash']
            if idx:
                previous=r['attempts'][0]
                assert previous['code'] and not previous['provider_error']
                expected=(previous['feedback'][:4000]+'\n修复并返回完整代码，保持题面接口。').replace('\r\n','\n')
                assert any(expected in m['content'].replace('\r\n','\n') for m in request['messages'])
                assert any(previous['code'].replace('\r\n','\n') in m['content'].replace('\r\n','\n') for m in request['messages'])
            native=a.get('platform_results',{}).get('codesys',{})
            if native:
                assert native['source_sha256']==a['code_hash']
                assert native['platform_identity']==s.load(root/'native_preflight.json')['codesys']['positive']['platform_identity']
            if a.get('judge',{}).get('model_check',{}).get('executed'):
                assert a['solved'],'Formal check ran before functional/native success'
        details.append(dict(job_id=job['job_id'],first_solved=r['first_try'],solved=r['solved'],
                            attempts=len(r['attempts']),stop_reason=r['stop_reason']))
    summary=metrics(cfg,plan)
    assert summary['recorded']==140 and summary['actual_requests']==len(events)==summary['new_events']
    assert s.money(s.BASELINE)+total==s.money(ledger['spent_cny'])<=s.money(170)
    if released:
        manifest=s.load(root/'release_manifest.json')
        assert manifest==s.load(s.MIRROR/'release_manifest.json')
        for name,digest in manifest['files'].items():
            assert s.sha(root/name)==digest==s.sha(s.MIRROR/name),name
        package=s.load(root/'package_manifest.json')
        assert s.sha(root/'验收包.zip')==package['sha256']==s.sha(s.MIRROR/'验收包.zip')
    return dict(acceptance_passed=True,planned=140,recorded=140,actual_requests=len(events),
                study_increment_cny=float(total),total_accounted_cny=ledger['spent_cny'],rows=summary['rows'],jobs=details,
                limits=dict(total_cap_cny=170,initial_review_checkpoint_cny=80),source_files=plan['files'])

def finalize(cfg,plan):
    root=Path(cfg['campaign_root'])
    assert not (root/'release_manifest.json').exists(),'Final release already frozen'
    result=audit_final(cfg,plan)
    summary=report(cfg,plan)
    s.atomic_json(root/'analysis.json',result)
    text=markdown(cfg,plan,summary)
    text+='\n## 最终验收\n\n已完成140题次，费用、模型身份、请求、候选和冻结版本逐条对应。失败保留分母。\n'
    text+='\n## 逐题结果\n\n|题次|首次功能通过|最终功能通过|候选数|停止原因|\n|---|---|---|---:|---|\n'
    for d in result['jobs']:text+=f"|{d['job_id']}|{d['first_solved']}|{d['solved']}|{d['attempts']}|{d['stop_reason']}|\n"
    text+='\n本实验验证工程流程在固定任务与配置下的可运行性，不单独证明某一种反馈的因果收益，也不证明稳定框架优势。\n'
    (root/'最终报告.md').write_bytes(text.encode())
    for job in plan['jobs']:
        record=s.load(root/'jobs'/job['condition']/(job['pid']+'.json'))
        for a in record['attempts']:
            native=a.get('platform_results',{}).get('codesys',{})
            if not native:continue
            for name in ('candidate.st','result.json','codesys_result.json'):
                source=Path(native['artifact_dir'])/name
                if source.exists():
                    target=root/'native_evidence'/job['condition']/job['pid']/str(a['idx'])/name
                    target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(source.read_bytes())
    mirror(root)
    files={p.relative_to(s.MIRROR).as_posix():s.sha(p) for p in s.MIRROR.rglob('*') if p.is_file()}
    s.atomic_json(root/'release_manifest.json',dict(kind=s.KIND,files=files,source_files=plan['files'],actual_requests=result['actual_requests']))
    mirror(root)
    archive=root/'验收包.zip'
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED) as z:
        for p in s.MIRROR.rglob('*'):
            if p.is_file():z.writestr('evidence/'+p.relative_to(s.MIRROR).as_posix(),p.read_bytes())
        for p in s.source_files():z.writestr('source/'+p.relative_to(s.REPO).as_posix(),p.read_bytes())
    with zipfile.ZipFile(archive) as z:assert z.testzip() is None
    s.atomic_json(root/'package_manifest.json',dict(sha256=s.sha(archive),entries=len(files)+1+len(s.source_files())))
    mirror(root);audit_final(cfg,plan,released=True)

def serve(cfg,port):
    root=Path(cfg['campaign_root'])
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path in ('/','/status.html'):
                content=html(cfg,s.load(root/'study_plan.json'),metrics(cfg,s.load(root/'study_plan.json'))).encode();mime='text/html; charset=utf-8'
            elif self.path in ('/最终报告.md','/验收包.zip'):
                target=root/self.path.lstrip('/')
                if not target.exists():self.send_error(404);return
                content=target.read_bytes();mime='application/zip' if target.suffix=='.zip' else 'text/plain; charset=utf-8'
            else:self.send_error(404);return
            self.send_response(200);self.send_header('Content-Type',mime);self.send_header('Content-Length',str(len(content)));self.end_headers();self.wfile.write(content)
        def log_message(self,*args):pass
    server=ThreadingHTTPServer(('127.0.0.1',port),Handler)
    s.atomic_json(root/'status_viewer.json',dict(**s.old.support.current_process_marker(),url=f'http://127.0.0.1:{port}/status.html'))
    print(f'http://127.0.0.1:{port}/status.html',flush=True);server.serve_forever()

"""Local read-only HTML status and human-review downloads; no model or billing writes."""
import argparse
from datetime import datetime, timedelta, timezone
from html import escape
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sys
from urllib.parse import quote, urlsplit

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'agent_dev_r9/scripts'))
from campaign_status import load, registered_process_alive
from resume_user_paused_campaign import current_process_marker

CFG = REPO / 'agent_dev_r9/config.r9_repair.json'
REVIEW = REPO / 'progress/review_liu_20261101/复核材料.html'
ZIP = REPO / 'progress/工艺复核材料_刘晏铭_20261101.zip'
CST = timezone(timedelta(hours=8))


def offline_page():
    active = load(REPO / 'progress/active_experiment.json')
    cfg = load(REPO / active.get('config', 'progress/v13/config.offline.json'))
    root = (REPO / cfg['campaign_root']).resolve()
    revision_root = (REPO / active.get('revision_root', 'progress/v13')).resolve()
    scores_path = (REPO / active.get('rescore_path', 'progress/evidence/v13_rescore_20261108b/rescore.json')).resolve()
    if not all(p.is_relative_to(REPO.resolve()) for p in (root, revision_root, scores_path)):
        raise RuntimeError('Offline status paths must stay in this repository')
    offline = load(root / 'offline.json')
    scores = load(scores_path)
    ledger = load(Path('E:/PLC_Dev/evidence/dmxapi_budget_75.json'))
    version = str(offline.get('version', 'v1.3'))
    reused = bool(offline.get('native_results_reused'))
    native_note = '已按同源码哈希及当前平台身份复用 r1 原生编译证据。' if reused else '参考解已执行真实平台编译。'
    native = []
    for label in ('codesys', 'openplc'):
        if reused:
            record = next((r for r in offline.get('native_evidence', []) if r['platform'] == label), {})
            rows = record.get('entries', [])
        else:
            rows = load(root / (label + '_references.json'))
        rows = rows if isinstance(rows, list) else []
        native.append(f'<li>{escape(label.upper())}：{sum(r.get("status") == "passed" for r in rows)}/35 参考解编译通过</li>')
    baseline_label = escape(str(scores.get('baseline_label', '旧版本地整题')))
    current_label = escape(str(scores.get('current_label', '修订版本地整题')))
    review_route = '/v13-r2-review.html' if version == 'v1.3-review-r2' else '/v13-review.html'
    repo_revision_path = quote(revision_root.relative_to(REPO.resolve()).as_posix())
    table = []
    for r in scores.get('rows', []):
        cells = [r['group'], f'{r["old_solved"]}/35', f'{r["new_solved"]}/35',
                 f'{r["new_passed"]}/531', ', '.join(r['lost']) or '无', len(r['tool_errors'])]
        table.append('<tr>' + ''.join('<td>' + escape(str(x)) + '</td>' for x in cells) + '</tr>')
    return f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="15"><title>PLC 修订验收状态</title><style>
body{{background:#f1f5fa;color:#203047;font:16px/1.7 system-ui,"Microsoft YaHei",sans-serif;margin:0}}
main{{max-width:1100px;margin:auto;padding:28px 22px}}section{{background:white;border:1px solid #dce5ef;border-radius:12px;padding:20px;margin:18px 0}}
table{{border-collapse:collapse;width:100%;font-size:14px}}td,th{{padding:10px;text-align:left;border-bottom:1px solid #e6ecf3}}a{{color:#155eab}}.scroll{{overflow:auto}}</style>
<main><h1>{escape(version)} 修订与免费验收</h1><p>当前没有付费模型实验运行。每 15 秒刷新本机证据。</p>
<section><h2>验收进度</h2><p>功能与严格接口：{offline.get('cases_passed', 0)}/{offline.get('cases', 531)} 条用例通过。</p><ul>{''.join(native)}</ul>
<p>{native_note}本页结果属于平台适配口径，不代表原始 VARIANT 接口通过率。</p>
<p>性质总数 {offline.get('total_properties', '—')}；原始 LTL {offline.get('raw_ltl', '—')}，运行期 LTL {offline.get('runtime_ltl', '—')}。测试轨迹检查不代表穷尽证明。</p></section>
<section><h2>固定历史候选的事后评分</h2><div class="scroll"><table><tr><th>组别</th><th>{baseline_label}</th><th>{current_label}</th><th>修订版通过用例</th><th>新增失败题</th><th>工具未决</th></tr>{''.join(table)}</table></div>
<p>两侧使用相同检查器及相同历史候选；不替换 R8 正式结果，不是新版提示的模型生成实验。</p></section>
<section><h2>人工复审与费用</h2><p>已收到上游复核记录2草稿：火焰题标批准，其余四题需修改；适用版本待确认。本修订版技术整改后待复审，未补造批准。</p>
<p>本阶段模型费用 ¥0；共享账本累计 ¥{ledger.get('spent_cny', 0):.6f}/75，原诊断额度未增加。</p>
<p><a href="{review_route}">查看修改后复审材料</a> · <a href="https://github.com/WtqMyou/plc-st-coding-agent/tree/main/{repo_revision_path}">GitHub 修订版</a></p></section></main></html>'''


def page():
    active = load(REPO / 'progress/active_experiment.json')
    if active.get('mode') == 'offline_review':
        return offline_page()
    selected_cfg = (REPO / active['config']).resolve() if active.get('config') else CFG
    if not selected_cfg.is_relative_to(REPO.resolve()):
        raise RuntimeError('Status configuration must stay in this repository')
    cfg = load(selected_cfg)
    root = Path(cfg['campaign_root'])
    state = load(root / 'study_state.json')
    summary = load(root / 'study_summary.json')
    plan = load(root / 'study_plan.json')
    ledger = load(cfg['budget_ledger_path'])
    sync = load(root / 'git_sync_status.json')
    alive = registered_process_alive(load(root / 'active_run.json'))
    title = {'prepared': '准备完成', 'running': '实验运行中', 'completed': '实验已结束', 'stopped': '实验已停止，需检查'}.get(state.get('state'), '正在读取状态')
    if state.get('state') == 'running' and not alive:
        title = '运行进程未找到，需检查'
    color = '#18764a' if alive or state.get('state') == 'completed' else '#996114'
    completed = int(summary.get('recorded', 0))
    planned = int(summary.get('planned', 8 if active else 16))
    total = ledger.get('spent_cny', 0)
    stage = total - plan.get('initial_spent_cny', total)
    stage_cap = float(plan.get('study_additional_cap_cny', 8))
    label = summary.get('label') or active.get('label') or 'R9 小规模多轮修复对照'
    reuse_note = ('含历史复用 ' + str(summary.get('reused_count', 0)) + ' 条；本轮新归档 ' +
                  str(summary.get('fresh_recorded', 0)) + '/' + str(summary.get('fresh_planned', 16)) + ' 条'
                  if 'reused_count' in summary else '完成数量包含失败，不等于通过数量')
    now = datetime.now(CST).strftime('%Y-%m-%d %H:%M:%S')
    current = str(state.get('current_job', '—'))
    elapsed = ''
    if alive and state.get('at'):
        minutes = max(0, (datetime.now(CST) - datetime.fromisoformat(state['at'])).total_seconds()) / 60
        elapsed = f' · 本题次已运行约 {minutes:.1f} 分钟'
    rows = []
    for r in summary.get('rows', []):
        framework = '自研' if r['framework'] == 'custom' else 'Codex'
        if r.get('model_id'):
            framework += ' / ' + {'deepseek-v4pro':'DeepSeek','minimax-m27':'MiniMax'}.get(r['model_id'],r['model_id'])
        values = [framework, f"{r['task_seconds']} 秒",
                  '暂缓，先修复功能' if r['verification_after_tests'] else '继续检查',
                  f"{r['attempted']}/{r['n']}", f"{r['first_solved']}/{r['n']}",
                  f"{r['solved']}/{r['n']}", r['repaired'], r['two_attempts']]
        rows.append('<tr>' + ''.join('<td>' + escape(str(v)) + '</td>' for v in values) + '</tr>')
    attention = '<p class="attention">' + escape(state.get('error', '')) + '</p>' if state.get('error') else ''
    repo_url = 'https://github.com/WtqMyou/plc-st-coding-agent'
    status_url = repo_url + '/blob/main/' + quote(active.get('status_path','progress/evidence/r9_repair_policy_20261101/实验状态.md'))
    sync_text = ('已同步至 GitHub' if sync.get('state') == 'synced' else '同步状态需检查')
    return f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="15">
<title>PLC 实验实时状态</title><style>
body{{margin:0;background:#f1f5fa;color:#203047;font:16px/1.7 system-ui,"Microsoft YaHei",sans-serif}}
main{{max-width:1180px;margin:auto;padding:30px 22px}}h1{{font-size:30px;margin:8px 0}}h2{{font-size:21px}}
.muted{{color:#65758b;font-size:14px}}.badge{{color:{color};font-weight:700}}
.cards{{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:16px;margin:22px 0}}
.card,.panel{{background:white;border:1px solid #dce5ef;border-radius:12px;padding:20px}}
.value{{font-size:31px;line-height:1.6;font-weight:700}}.bar{{height:10px;background:#e8eef5;border-radius:10px;overflow:hidden}}
.bar span{{display:block;height:100%;background:#2671c7;width:{min(100, max(0, completed / max(1, planned) * 100)):.1f}%}}
.panel{{margin:18px 0}}.scroll{{overflow-x:auto}}table{{border-collapse:collapse;width:100%;font-size:14px}}
td,th{{text-align:left;white-space:nowrap;padding:11px 9px;border-bottom:1px solid #e6ecf3}}
th{{background:#f7f9fc}}a{{color:#155eab}}.links a{{display:inline-block;margin:5px 18px 5px 0}}
code{{overflow-wrap:anywhere;background:#f2f6fa;padding:3px 6px}}.attention{{color:#a43325}}
</style><main><div class="muted">PLC ST Coding Agent · {escape(label)}</div>
<h1>实验实时状态</h1><div class="badge">● {escape(title)}</div>
<p class="muted">本机数据 · 每 15 秒自动刷新 · 页面读取时间 {now}（北京时间）</p>
<div class="cards"><section class="card"><div>已归档题次</div><div class="value">{completed} / {planned}</div>
<div class="bar"><span></span></div><div class="muted">{escape(reuse_note)}</div></section>
<section class="card"><div>本阶段累计计入</div><div class="value">¥{stage:.3f}</div><div class="muted">阶段上限 ¥{stage_cap:g}，包含在途预留</div></section>
<section class="card"><div>全部实验累计计入</div><div class="value">¥{total:.3f}</div><div class="muted">总授权 ¥75，未增加额度</div></section>
<section class="card"><div>原诊断阶段累计增量</div><div class="value">¥{total - 34.011998:.3f}</div><div class="muted">原追加上限 ¥10，接续不重置</div></section></div>
<section class="panel"><h2>当前执行</h2><p><code>{escape(current)}</code>{escape(elapsed)}</p>{attention}
<p class="muted">运行依赖这台笔记本保持开机联网。页面关闭不停止实验；实验停止后会显示结束或需检查。</p></section>
<section class="panel"><h2>各条件进度与结果</h2><div class="scroll"><table><thead><tr>
<th>框架</th><th>单题预算</th><th>功能失败后的 LTL</th><th>已尝试</th><th>首轮通过</th><th>最终通过</th><th>修复新增成功</th><th>两次尝试</th>
</tr></thead><tbody>{''.join(rows)}</tbody></table></div>
<p class="muted">结果表按实验检查点更新：{escape(str(summary.get('updated_at', '尚无记录')))}。两题小样本不能证明稳定优势；费用按本次页面读取时的账本展示，包含预留，并非供应商实际账单。</p></section>
<section class="panel"><h2>GitHub 与人工复核</h2><p>{sync_text} · 提交 {escape(str(sync.get('commit', ''))[:8])}
<span class="muted"> · {escape(str(sync.get('at', '')))}</span></p>
<p>刘晏铭：五道新增工业题待人工核对，材料已整理，结论尚未填写。</p><div class="links">
<a href="{status_url}" target="_blank" rel="noopener">GitHub 状态快照</a><a href="{repo_url}" target="_blank" rel="noopener">项目仓库</a>
<a href="/review.html" target="_blank">查看五题复核材料</a><a href="/review.zip">下载给刘晏铭的材料包</a></div></section></main></html>'''


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        path = urlsplit(self.path).path
        if path in ('/', '/status.html'):
            raw, mime = page().encode('utf-8'), 'text/html; charset=utf-8'
        elif path == '/review.html':
            raw, mime = REVIEW.read_bytes(), 'text/html; charset=utf-8'
        elif path == '/v13-review.html':
            raw, mime = (REPO / 'progress/v13/复审材料.html').read_bytes(), 'text/html; charset=utf-8'
        elif path == '/v13-r2-review.html':
            raw, mime = (REPO / 'progress/v13_r2/复审材料.html').read_bytes(), 'text/html; charset=utf-8'
        elif path == '/review.zip':
            raw, mime = ZIP.read_bytes(), 'application/zip'
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(raw)))
        if path == '/review.zip':
            self.send_header('Content-Disposition', 'attachment; filename="review_liu_20261101.zip"')
        self.end_headers()
        self.wfile.write(raw)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8879)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    active = load(REPO / 'progress/active_experiment.json')
    selected_cfg = REPO / active['config'] if active.get('config') else CFG
    root = Path(load(selected_cfg)['campaign_root'])
    marker = dict(**current_process_marker(), url=f'http://127.0.0.1:{server.server_port}/status.html')
    (root / 'status_viewer.json').write_text(json.dumps(marker, ensure_ascii=False, indent=2), encoding='utf-8')
    print(marker['url'], flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()

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
ACTIVE_POINTER = REPO / 'progress/active_experiment.json'


def offline_page():
    active = load(ACTIVE_POINTER)
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
    native_note = '已按同源码哈希及当前平台身份复用历史原生编译证据。' if reused else '参考解已执行真实平台编译。'
    combined_native = load(root / 'native_references.json')
    if isinstance(combined_native,list) and combined_native:
        native_note = f'本版新增 {offline.get("native_fresh",0)} 次参考编译，按相同源码与当前编译器身份复用 {offline.get("native_reused",0)} 份。'
    native = []
    for label in ('codesys', 'openplc'):
        if isinstance(combined_native,list) and combined_native:
            rows = [r for r in combined_native if r.get('platform') == label]
        elif reused:
            record = next((r for r in offline.get('native_evidence', []) if r['platform'] == label), {})
            rows = record.get('entries', [])
        else:
            rows = load(root / (label + '_references.json'))
        rows = rows if isinstance(rows, list) else []
        native.append(f'<li>{escape(label.upper())}：{sum(r.get("status") == "passed" for r in rows)}/35 参考解编译通过</li>')
    baseline_label = escape(str(scores.get('baseline_label', '旧版本地整题')))
    current_label = escape(str(scores.get('current_label', '修订版本地整题')))
    review_route = active.get('review_route') or ('/v13-r2-review.html' if version == 'v1.3-review-r2' else '/v13-review.html')
    if review_route not in ('/v13-review.html','/v13-r2-review.html','/v13-r4-review.html','/v13-r6-review.html','/v13-r8-review.html'):
        raise RuntimeError('Unknown review route')
    repo_revision_path = quote(revision_root.relative_to(REPO.resolve()).as_posix())
    native_probes_note = ('新增 ' + str(offline.get('native_probes_count',0)) + ' 项原生对照（含预期失败），平台接受不等于运行正确。'
                         if offline.get('native_probes_count') else '')
    data_note = str(offline.get('data_note') or ('数据仍为 ' + str(offline['data_version']) + '；本次只改变裁判。' if offline.get('data_version') else ''))
    table = []
    for r in scores.get('rows', []):
        task_count = r.get('tasks',35)
        cells = [r['group'], f'{r["old_solved"]}/{task_count}', f'{r["new_solved"]}/{task_count}',
                 f'{r["new_passed"]}/{r.get("new_cases",offline.get("cases",531))}', ', '.join(r['lost']) or '无', len(r['tool_errors'])]
        table.append('<tr>' + ''.join('<td>' + escape(str(x)) + '</td>' for x in cells) + '</tr>')
    depth_rows = load(root / 'depth_diagnostics.json').get('results',[])
    depth_note = ''
    if depth_rows:
        rows = ''.join('<tr>'+''.join('<td>'+escape(str(value))+'</td>' for value in
            (r['pid'],r.get('actual_depth','—'),r.get('complete_depth','—'),8))+'</tr>' for r in depth_rows)
        depth_note = '<section><h2>形式检查实际范围</h2><p>下表是每题5秒的免费诊断，题库名义上限为8拍。到达某拍不代表这一层已完整展开；这六题均发生预算截断。</p><table><tr><th>题号</th><th>最深到达</th><th>完整展开</th><th>名义上限</th></tr>'+rows+'</table><p>缩小输入域的变异诊断单独存档，不计入正式通过率。</p></section>'
    handout_link = ' · <a href="/v13-r4-review.zip">下载给刘晏铭的r4复审包</a>' if version=='v1.3-review-r4' else ''
    repair_note = ''
    if version=='v1.3-judge-r5':
        explanation_url = 'https://github.com/WtqMyou/plc-st-coding-agent/blob/main/' + quote('progress/evidence/v13_r5_20261108/结果说明.md')
        repair_note = '<section><h2>这次修复解决了什么</h2><p>通用整数转换和RETURN提前退出已修复。原FIFO答卷通过27/27功能用例，但形式检查仍发现S4反例：满队同拍入出队后，数量变为1却仍返回满队状态码。</p><p>未修改原答卷，也没有更换小试验原选中轮次。历史140份固定答案的分数变化属于裁判纠错，不能当作模型生成能力提升。</p><p><a href="'+explanation_url+'">查看归因、反例和完整复验结果</a></p></section>'
    if version=='v1.3-review-r6':
        repair_note = '<section><h2>11.10资料处理</h2><p>已核验四份来件，修复危险液位复位、无效配方编号和灌装INT上限。原583条断言保留，补入568条兼容断言。新分母含扩展轨迹的旧前缀，不等于独立样本数。</p><p>果酱泵毫秒接口、需求升档时备泵重选、闸门遇障动作仍待明确，冲突内容已留档。319条公式通过测试轨迹检查，2条旧公式轨迹不足；没有转借上游320条有界证明。</p><p><a href="/v13-r6-review.html">当前35题材料</a> · <a href="/v13-r6-record.md">复审记录模板</a> · <a href="/v13-r6-analysis.md">完整采纳说明</a></p></section>'
    human_note = '刘晏铭的本版工艺复审待填写；已收到的旧稿与新意见均留档，旧版批准不自动适用于当前修订版。'
    if version=='v1.3-review-r8':
        repair_note = '<section><h2>lym返回规则已落实</h2><p>果酱泵使用毫秒接口；需求升档时重选备泵；闸门任何状态遇障均立即停机锁故障，解除后须新的双键组合沿复位。</p><p>三题契约改变，表中只比较其余32题和1113条相同功能断言。三题的旧答案单独诊断，不当作新的35题四组实验。</p><p>349条非空公式均通过参考测试轨迹核验，另23条仿真性质；这不是全输入和全深度的形式证明。</p><p><a href="/v13-r8-review.html">查看当前35题</a> · <a href="/v13-r8-analysis.md">查看返回包采纳与验收说明</a></p></section>'
        human_note = '已收到lym的13题修订与本地验算，明确的三项规则已采用。返回包未附填写后的逐题签署表，登记为收到修订并技术验收，未推定全部题目人工批准。'
    raw_ltl_note = f'原始 LTL {offline["raw_ltl"]}，' if 'raw_ltl' in offline else ''
    return f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="15"><title>PLC 修订验收状态</title><style>
body{{background:#f1f5fa;color:#203047;font:16px/1.7 system-ui,"Microsoft YaHei",sans-serif;margin:0}}
main{{max-width:1100px;margin:auto;padding:28px 22px}}section{{background:white;border:1px solid #dce5ef;border-radius:12px;padding:20px;margin:18px 0}}
table{{border-collapse:collapse;width:100%;font-size:14px}}td,th{{padding:10px;text-align:left;border-bottom:1px solid #e6ecf3}}a{{color:#155eab}}.scroll{{overflow:auto}}</style>
<main><h1>{escape(version)} 修订与免费验收</h1><p>当前没有付费模型实验运行。每 15 秒刷新本机证据。</p>
<p>{escape(data_note)}</p>
<section><h2>验收进度</h2><p>功能与严格接口：{offline.get('cases_passed', 0)}/{offline.get('cases', 531)} 条用例通过。</p><ul>{''.join(native)}</ul>
<p>{native_note}本页结果属于平台适配口径，不代表原始 VARIANT 接口通过率。</p>
<p>{escape(native_probes_note)}</p>
<p>性质总数 {offline.get('total_properties', '—')}；{raw_ltl_note}非空公式 {offline.get('runtime_ltl', '—')}。测试轨迹检查不代表穷尽证明。</p></section>
<section><h2>固定历史候选的事后评分</h2><div class="scroll"><table><tr><th>组别</th><th>{baseline_label}</th><th>{current_label}</th><th>修订版通过用例</th><th>新增失败题</th><th>工具未决</th></tr>{''.join(table)}</table></div>
<p>同一批历史答卷，保留原选中轮次；数据与裁判版本见表头，用例分母可能不同。不替换R8正式结果，也不表示模型生成能力提升。</p></section>
{depth_note}
{repair_note}
<section><h2>人工复审与费用</h2><p>{human_note}</p>
<p>本阶段模型费用 ¥0；共享账本累计 ¥{ledger.get('spent_cny', 0):.6f}/75，原诊断额度未增加。</p>
<p><a href="{review_route}">查看修改后复审材料</a> · <a href="https://github.com/WtqMyou/plc-st-coding-agent/tree/main/{repo_revision_path}">GitHub 修订版</a>{handout_link}</p></section></main></html>'''


def page():
    active = load(ACTIVE_POINTER)
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
                  f"{r['solved']}/{r['n']}", r['repaired'], r['two_attempts'],
                  r.get('calls','—'),r.get('mc_executed','—'),r.get('wall_seconds','—')]
        rows.append('<tr>' + ''.join('<td>' + escape(str(v)) + '</td>' for v in values) + '</tr>')
    attention = '<p class="attention">' + escape(state.get('error', '')) + '</p>' if state.get('error') else ''
    repo_url = 'https://github.com/WtqMyou/plc-st-coding-agent'
    review_route = escape(active.get('review_route','/review.html'),quote=True)
    handout_route = escape(active.get('handout_route','/review.zip'),quote=True)
    result_note = ''
    acceptance = load(root / 'acceptance.json')
    if 'posthoc_language_modeling_inconclusive_jobs' in acceptance:
        result_url = repo_url + '/blob/main/' + quote('progress/evidence/r4_check_order_20261108/结论与调整建议.md')
        result_note = f'''<section class="panel"><h2>本轮结论</h2><p>8/8题次结束，15次模型请求，本轮计入¥{acceptance['study_charged_cny']:.6f}。两框架后置条件各通过1/2，持续检查条件各为0/2；各条件实际形式检查均为1次，未证实稳定准确率收益。</p>
<p>事后复核发现1个语言建模未决：TO_INT原候选在CODESYS和OpenPLC都接受编译，本地裁判尚不支持。不能把它当作已确认的模型语法错误，也不能仅凭编译通过补算功能成功。原r4分数保留。</p>
<p><a href="{result_url}" target="_blank" rel="noopener">查看结果分析与下一步调整</a></p></section>'''
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
<th>框架</th><th>单题预算</th><th>功能失败后的 LTL</th><th>已尝试</th><th>首轮通过</th><th>最终通过</th><th>第二轮新增成功</th><th>两次尝试</th><th>请求数</th><th>形式检查次数</th><th>耗时秒</th>
</tr></thead><tbody>{''.join(rows)}</tbody></table></div>
<p class="muted">结果表按实验检查点更新：{escape(str(summary.get('updated_at', '尚无记录')))}。两题小样本不能证明稳定优势；费用按本次页面读取时的账本展示，包含预留，并非供应商实际账单。</p></section>
{result_note}
<section class="panel"><h2>GitHub 与人工复核</h2><p>{sync_text} · 提交 {escape(str(sync.get('commit', ''))[:8])}
<span class="muted"> · {escape(str(sync.get('at', '')))}</span></p>
<p>刘晏铭：r4工艺复审待确认，材料包含五道工业题和三道本次修订题。</p><div class="links">
<a href="{status_url}" target="_blank" rel="noopener">GitHub 状态快照</a><a href="{repo_url}" target="_blank" rel="noopener">项目仓库</a>
<a href="{review_route}" target="_blank">查看复审材料</a><a href="{handout_route}">下载给刘晏铭的材料包</a></div></section></main></html>'''


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
        elif path == '/v13-r4-review.html':
            raw, mime = (REPO / 'progress/v13_r4/复审材料.html').read_bytes(), 'text/html; charset=utf-8'
        elif path == '/v13-r6-review.html':
            raw = (REPO / 'progress/v13_r6/复审材料.html').read_text('utf-8')
            raw = raw.replace('href="复审记录.md"','href="/v13-r6-record.md"').replace('href="采纳与核验.md"','href="/v13-r6-analysis.md"')
            raw, mime = raw.encode('utf-8'), 'text/html; charset=utf-8'
        elif path == '/v13-r6-record.md':
            raw, mime = (REPO / 'progress/v13_r6/复审记录.md').read_bytes(), 'text/plain; charset=utf-8'
        elif path == '/v13-r6-analysis.md':
            raw, mime = (REPO / 'progress/v13_r6/采纳与核验.md').read_bytes(), 'text/plain; charset=utf-8'
        elif path == '/v13-r8-review.html':
            raw, mime = (REPO / 'progress/v13_r8/复审材料.html').read_bytes(), 'text/html; charset=utf-8'
        elif path == '/v13-r8-analysis.md':
            raw, mime = (REPO / 'progress/v13_r8/README.md').read_bytes(), 'text/plain; charset=utf-8'
        elif path == '/v13-r4-review.zip':
            raw, mime = (REPO / 'progress/工艺复审_r4_刘晏铭_20261108.zip').read_bytes(), 'application/zip'
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
        elif path == '/v13-r4-review.zip':
            self.send_header('Content-Disposition', 'attachment; filename="review_r4_liu_20261108.zip"')
        self.end_headers()
        self.wfile.write(raw)


def main():
    global ACTIVE_POINTER
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8879)
    parser.add_argument('--active', default='progress/active_experiment.json')
    args = parser.parse_args()
    ACTIVE_POINTER = (REPO / args.active).resolve()
    if not ACTIVE_POINTER.is_relative_to(REPO.resolve()):
        raise RuntimeError('Viewer selection must stay in this repository')
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    active = load(ACTIVE_POINTER)
    selected_cfg = REPO / active['config'] if active.get('config') else CFG
    root = (REPO / load(selected_cfg)['campaign_root']).resolve()
    marker = dict(**current_process_marker(), url=f'http://127.0.0.1:{server.server_port}/status.html')
    (root / 'status_viewer.json').write_text(json.dumps(marker, ensure_ascii=False, indent=2), encoding='utf-8')
    print(marker['url'], flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()

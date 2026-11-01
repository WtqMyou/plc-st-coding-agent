"""Create a portable review handout without changing frozen experiment inputs."""
from datetime import datetime
import hashlib
import html
import json
from pathlib import Path
import re
import sys
import zipfile

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / 'agent_dev_r9'
sys.path.insert(0, str(SOURCE))
from stbench.campaign import digest, tasks

NAME = 'review_liu_20261101'
OUT = REPO / 'progress' / NAME
ARCHIVE = REPO / 'progress/工艺复核材料_刘晏铭_20261101.zip'
PIDS = ('self-hard-05', 'self-hard-06', 'self-hard-07', 'self-medium-05', 'self-medium-06')
FOCUS = {
    'self-hard-05': ['熄火同拍跳闸、燃料许可与风量输出的关系是否明确？',
                     '氧量分析仪故障仅切除修正的设定是否适合本题边界？',
                     '复位上升沿及其前置条件、修正和风量的限幅是否合理？'],
    'self-hard-06': ['压力单位 kPa，4500 跳闸与 4200 复位的闭区间和滞环是否明确？',
                     '压力数据失效与复位的优先关系是否清楚？',
                     '卡滞连续三拍及中断清零、线索位和历史足迹是否一致？三拍依赖扫描周期的假设是否应补充？'],
    'self-hard-07': ['三模式含义、初始化/故障/复位/模式切换的优先关系是否一致？',
                     '切换当拍保持阀位、不积分，以及积分预置和输出限幅是否对应？',
                     '给定 PI 参数、流量单位、手动输入范围和有效扫描周期的假设是否完整？'],
    'self-medium-05': ['蒸汽和燃料流量 kg/s 与秒、吨的换算是否一致？',
                       '温度/压力闭区间端点、数据故障冻结、复位当拍不累计是否对应？',
                       '产量与燃料累计条件的差异、收益和成本题内常数是否写清楚？'],
    'self-medium-06': ['误差及误差变化率的单位、采样周期与归一化范围是否清楚？',
                       '九条规则和加权输出、功率限幅与修正量的区别是否一致？',
                       '首次扫描、禁用、故障和复位清除历史后的恢复行为是否覆盖？'],
}


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x', encoding='utf-8', newline='\n') as stream:
        stream.write(text)


def main():
    if OUT.exists() or ARCHIVE.exists():
        raise RuntimeError('Review package already exists; use a new version rather than replace it')
    selected = {p.pid: (original, p, ref) for original, p, ref in tasks() if p.pid in PIDS}
    audit_path = SOURCE / 'evidence/r9_material_audit_20261101b/human_review.json'
    audit = {r['pid']: r for r in json.loads(audit_path.read_text(encoding='utf-8'))}
    rows = []
    articles = []
    records = ['# 五题工艺复核记录', '', '指定负责人：刘晏铭；以下均为待填写，不代表已经审阅。', '',
               '请逐题填写“通过 / 需修改 / 无法确认”，列出问题和建议，再填写实际审阅人及日期。',
               '无法确认的单位、阈值或工况请明确标出；不要用自动测试通过代替人工结论。', '']
    for pid in PIDS:
        original, problem, reference = selected[pid]
        data = problem.to_dict()
        original_path = SOURCE / 'datasets/selfmade' / (pid + '.json')
        original_raw = original_path.read_bytes()
        assert json.loads(original_raw)['pid'] == pid
        target = OUT / 'original' / (pid + '.json')
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as stream:
            stream.write(original_raw)
        write(OUT / 'adapted' / (pid + '.json'), json.dumps(data, ensure_ascii=False, indent=2) + '\n')
        write(OUT / 'reference' / (pid + '.st'), reference)
        rows.append(f"|{pid}|{problem.title}|{audit[pid]['automatic_reference_cases']}|待人工复核|")
        focus = FOCUS[pid]
        text = [f'# {pid}：{problem.title}', '', '状态：待人工复核；指定负责人刘晏铭。', '',
                '## 建议核对', ''] + ['- ' + item for item in focus]
        text += ['', '## 题目与平台适配要求', '', problem.requirements, '', '## 接口', '',
                 '|变量|方向|类型|说明|', '|---|---|---|---|']
        direction = {'input': '输入', 'output': '输出', 'inout': '输入输出'}
        for variable in data['variables']:
            text.append('|'+ '|'.join(str(v).replace('|', '\\|').replace('\n', ' ') for v in
                (variable['name'], direction.get(variable['direction'], variable['direction']),
                 variable['data_type'], variable['description'])) + '|')
        text += ['', '## 性质说明', '']
        for spec in data['specs']:
            mechanism = '已有 LTL 公式；实际结论以检查记录为准' if spec.get('ltl') else '目前仅测试覆盖'
            text += [f"- {spec['sid']}：{spec['text']}（{mechanism}）"]
        text += ['', '## 当前平台适配参考程序', '', '```st', reference, '```', '',
                 '## 当前测试用例（含期望值，供人工复核）', '', '```json',
                 json.dumps(data['test_cases'], ensure_ascii=False, indent=2), '```', '']
        write(OUT / '题目' / (pid + '.md'), '\n'.join(text))
        variables = ''.join('<tr>' + ''.join('<td>' + html.escape(str(value)) + '</td>' for value in
            (v['name'], direction.get(v['direction'], v['direction']), v['data_type'], v['description'])) + '</tr>'
            for v in data['variables'])
        specs = ''.join('<li><b>' + html.escape(s['sid']) + '</b> ' + html.escape(s['text']) +
                         (' <small>已有公式</small>' if s.get('ltl') else ' <small>仅测试覆盖</small>') + '</li>'
                        for s in data['specs'])
        articles.append(f'<article id="{pid}"><h2>{pid} · {html.escape(problem.title)}</h2>'
            '<p class="pending">待人工复核</p><h3>建议核对</h3><ul>' +
            ''.join('<li>' + html.escape(item) + '</li>' for item in focus) + '</ul>' +
            '<h3>题目与平台适配要求</h3><pre>' + html.escape(problem.requirements) + '</pre>' +
            '<h3>接口</h3><div class="scroll"><table><thead><tr><th>变量</th><th>方向</th><th>类型</th><th>说明</th>'
            '</tr></thead><tbody>' + variables + '</tbody></table></div><h3>性质说明</h3><ul>' + specs + '</ul>' +
            '<details><summary>展开参考 ST 程序</summary><pre class="code">' + html.escape(reference) + '</pre></details>' +
            '<details><summary>展开测试与期望值</summary><pre class="code">' +
            html.escape(json.dumps(data['test_cases'], ensure_ascii=False, indent=2)) + '</pre></details></article>')
        records += [f'## {pid}：{problem.title}', '', '- 结论：待填写（通过 / 需修改 / 无法确认）',
                    '- 问题或未覆盖工况：', '- 修改建议：', '- 实际审阅人：', '- 审阅日期：', '']
    guide = '\n'.join(['# 发给刘晏铭的五题工艺复核材料', '',
        '用途：组内核对新增课程题目的工艺假设、参考程序和测试是否自洽。自动检查核对程序与已有断言；人工复核还要判断题目、断言和边界是否合理。', '',
        '解压后先打开“复核材料.html”，可在浏览器离线查看全部五题，再填写“复核记录.md”。不需要模型 API、编程环境或重跑付费实验。', '',
        '|题号|主题|既有参考用例检查|人工状态|', '|---|---|---|---|'] + rows + ['',
        '请核对：单位/量程/周期；阈值和边界；失效处理；故障与复位的优先级；参考实现与题意；测试遗漏。', '',
        '每题回复“通过 / 需修改 / 无法确认”，附问题、建议、实际审阅人和日期。不了解的工艺假设可标为无法确认。', '',
        '## 材料版本与说明', '',
        '- 来源为当前 R9 portable-frame-v5。部分原 dt 接口改为 scanSeconds，单位秒，原数字期望不变。',
        '- original/ 保存原始 JSON；adapted/ 保存实际评测采用的适配题目；reference/ 保存对应 ST 参考程序；题目/ 是可直接在 GitHub 阅读的展开材料。',
        '- 原始 provenance 中的“人工审核”措辞是上游来源声明，其完成状态未独立确认，本次不得当作刘晏铭的审核结论。',
        '- 既有自动用例通过不代表工艺确认，LTL 只表示已建公式，不代表所有性质已证明。',
        '- 本材料用于课程项目质量复核，审核范围及无法确认事项应记录清楚。',
        '- 当前指定负责人为刘晏铭，所有人工结论、日期和签署仍待实际填写。',
        '- 源码摘要：`' + digest() + '`。', ''])
    write(OUT / 'README.md', guide)
    write(OUT / '复核记录.md', '\n'.join(records))
    navigation = ''.join(f'<a href="#{pid}">{pid}</a>' for pid in PIDS)
    page = ('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>五题工艺复核材料 · 刘晏铭</title><style>'
        'body{margin:0;background:#f2f5f9;color:#1c2b40;font:16px/1.8 system-ui,"Microsoft YaHei",sans-serif}'
        'main{max-width:1050px;margin:auto;padding:32px 20px}h1{font-size:29px}h2{font-size:22px}'
        'article,.intro{background:white;padding:26px;margin:24px 0;border:1px solid #dce4ed;border-radius:12px}'
        'nav a{display:inline-block;margin:4px 14px 4px 0;color:#1558a2}pre{white-space:pre-wrap;overflow-wrap:anywhere}'
        '.code{background:#f5f7fa;padding:18px;font:13px/1.65 Consolas,monospace}'
        'table{width:100%;border-collapse:collapse;font-size:14px}th,td{text-align:left;border-bottom:1px solid #dce4ed;padding:9px}'
        '.scroll{overflow:auto}summary{cursor:pointer;color:#1558a2;padding:12px 0}.pending{color:#97540b}small{color:#65758a}'
        '@media print{body{background:white}article{break-before:page;border:0}details{display:block}}</style>'
        '<main><h1>五题工艺复核材料</h1><div class="intro"><p>指定负责人：刘晏铭 · 状态：待人工复核</p>'
        '<p>请核对题目、参考答案和测试的单位、阈值、故障/复位优先级及未覆盖工况。已有自动测试通过不替代人工判断。</p>'
        '<p>逐题回复：通过 / 需修改 / 无法确认，并附问题、建议、实际审阅人和日期。填写同包的“复核记录.md”即可。</p>'
        '<p>本页可离线浏览，不调用模型，不运行设备。原始来源中的审核措辞尚未独立确认，本材料没有预填通过结论。</p><nav>' +
        navigation + '</nav></div>' + ''.join(articles) + '</main></html>')
    write(OUT / '复核材料.html', page)
    files = sorted(p for p in OUT.rglob('*') if p.is_file())
    manifest = dict(created_at=datetime.now().astimezone().isoformat(), source_sha256=digest(),
                    assigned_reviewer='刘晏铭', human_review_status='pending', reviewer=None, review_date=None, signoff=None,
                    files=[dict(path=p.relative_to(OUT).as_posix(), bytes=p.stat().st_size,
                                sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in files])
    write(OUT / 'manifest.json', json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    files.append(OUT / 'manifest.json')
    for p in files:
        if re.search(rb'\b(?:sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})', p.read_bytes()):
            raise RuntimeError('Credential-like text blocked: ' + p.name)
    with zipfile.ZipFile(ARCHIVE, 'x', zipfile.ZIP_DEFLATED) as archive:
        for p in files:
            archive.write(p, NAME + '/' + p.relative_to(OUT).as_posix())
    with zipfile.ZipFile(ARCHIVE) as archive:
        for p in files:
            assert archive.read(NAME + '/' + p.relative_to(OUT).as_posix()) == p.read_bytes()
    receipt = dict(package=ARCHIVE.relative_to(REPO).as_posix(), files=len(files), bytes=ARCHIVE.stat().st_size,
                   sha256=hashlib.sha256(ARCHIVE.read_bytes()).hexdigest(), archive_verified=True,
                   original_json_byte_copies_verified=all((OUT/'original'/f'{pid}.json').read_bytes() ==
                       (SOURCE/'datasets/selfmade'/f'{pid}.json').read_bytes() for pid in PIDS),
                   human_review_status='pending')
    write(ARCHIVE.with_suffix('.qa.json'), json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(receipt, ensure_ascii=False))


if __name__ == '__main__':
    main()

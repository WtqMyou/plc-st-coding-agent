"""Build the offline catalogue from the same JSON files read by run.py."""
import argparse
import html
import json
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "修订题面与用例表.html"

STYLE = """
:root{color:#1d2c32;background:#f7f7f3;font-family:"Segoe UI","Microsoft YaHei",sans-serif;line-height:1.65}
body{margin:auto;max-width:85rem;padding:2.5rem clamp(1rem,3vw,3rem) 5rem}
header,nav,article{margin-bottom:2rem}h1,h2,h3,h4{line-height:1.3}
h1{margin:0}h2{margin:0 0 .6rem}h3{margin:1.5rem 0 .55rem}
h4{margin:.8rem 0 .35rem}p{max-width:78ch}a{color:#075c65;text-underline-offset:.17em}
.summary{font-weight:600;color:#314c4b}.index{columns:3 17rem;list-style:none;padding:0}
.index li{break-inside:avoid;padding:.12rem 0}
article{background:white;border-top:3px solid #437477;padding:clamp(.8rem,2vw,1.5rem)}
code,pre{font-family:Consolas,"Microsoft YaHei",monospace;font-size:.92em}
pre{white-space:pre-wrap;overflow-wrap:anywhere;margin:.2rem 0}
.requirements{white-space:pre-wrap;max-width:95ch}table{border-collapse:collapse;width:100%;font-size:.9rem}
.scroll{overflow:auto}th,td{text-align:left;vertical-align:top;border-bottom:1px solid #d7dfdd;
padding:.4rem .55rem;overflow-wrap:anywhere}th{background:#edf3f1}td.note{min-width:9rem}
.cases{min-width:58rem}.cases pre{min-width:4rem}.pid{color:#4e6369;font-size:.9rem}
.end{display:block;margin-top:1rem}
@media print{body{max-width:none;padding:0;background:white}nav,.end{display:none}article{break-before:page;padding:0}
.scroll{overflow:visible}.cases{min-width:0}tr{break-inside:avoid}table{font-size:8pt}thead{display:table-header-group}}
"""


def esc(value):
    return html.escape(str(value), quote=True)


def json_cell(value):
    return "<pre>" + esc(json.dumps(value, ensure_ascii=False, sort_keys=True)) + "</pre>"


def table(headers, rows, css=""):
    # Rows contain trusted markup with every dataset value already escaped.
    head = "".join(f'<th scope="col">{esc(name)}</th>' for name in headers)
    body = "".join("<tr>" + "".join(f"<td>{cell}</td>" for cell in row) + "</tr>" for row in rows)
    return f'<div class="scroll"><table class="{css}"><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>'


def interface_rows(variables, prefix=""):
    for var in variables:
        name = prefix + var["name"]
        yield [f'<code>{esc(name)}</code>', esc(var["direction"]), esc(var["data_type"]), esc(var["description"])]
        if var.get("fields"):
            field_prefix = name + ("[]." if var["data_type"].lstrip().upper().startswith("ARRAY") else ".")
            yield from interface_rows(var["fields"],field_prefix)


def render_problem(data, path):
    pid = data["pid"]
    ident = esc(pid)
    groups = {}
    default_mode = data.get("case_mode") or "single"
    for case in data["test_cases"]:
        key = (case.get("group", ""), case.get("mode") or default_mode)
        if key[1] not in ("single","sequence"):
            raise ValueError(f"{pid}: unsupported mode {key[1]}")
        groups.setdefault(key, []).append(case)
    rel = quote(path.relative_to(ROOT).as_posix(), safe="/")
    public = data["source"] == "public"
    if public and not data.get("raw_text", "").strip():
        raise ValueError(f"{pid}: missing course source text")
    sections = [
        f'<article id="{ident}"><div class="pid"><code>{ident}</code></div><h2>{esc(data["title"])}</h2>',
        f'<div>{esc(data["target_pou"])} · {len(data["test_cases"])} 条功能用例 · <a href="{esc(rel)}">题目 JSON</a></div>',
    ]
    if public:
        sections.extend([
            '<h3>课程原文（含接口）</h3>',
            '<pre class="course-text">' + esc(data["raw_text"]) + '</pre>',
        ])
    else:
        sections.extend([
            '<h3>题面</h3>',
            '<div class="requirements">' + esc(data["requirements"]) + '</div>',
        ])
    sections.extend(['<h3>判分接口</h3>', table(("变量或字段","方向","类型","说明"),interface_rows(data["variables"]))])
    specs = [
        [esc(s["sid"]), esc(s["text"]), "<pre>" + esc(s["ltl"]) + "</pre>" if s.get("ltl") else "—",
         esc(s["kind"]), esc(s.get("verified_by") or "—")]
        for s in data["specs"]
    ]
    sections.extend(['<h3>规约</h3>', table(("编号", "性质", "公式", "类别", "数据标注的核对方式"), specs),
                     '<h3>功能用例</h3>'])
    for (group,mode),cases in groups.items():
        semantics = "每条使用新实例" if mode=="single" else "组内依次执行，同一实例保留状态"
        sections.append(f'<h4>{esc(group or "默认组")} · <code>{esc(mode)}</code> · {semantics} · {len(cases)} 条</h4>')
        has_schedule = any(c.get("scan_interval_ms") is not None for c in cases)
        has_options = any(c.get("expected_any") for c in cases)
        headers = ["用例","扫描拍数"]
        if has_schedule:
            headers.append("扫描间隔 scan_interval_ms（毫秒）")
        headers.extend(["初态／当条预置","常量输入","当条输入","必需期望 expected"])
        if has_options:
            headers.append("允许的输出组合 expected_any（任选一组）")
        headers.extend(["断言范围","说明"])
        rows = []
        for c in cases:
            cells = [f'<code>{esc(c["tc_id"])}</code>',str(max(1,int(c.get("cycles") or 1)))]
            if has_schedule:
                interval = c.get("scan_interval_ms")
                cells.append("—" if interval is None else esc(interval))
            cells.extend([json_cell(c.get("init") or {}),json_cell(c.get("const_inputs") or {}),
                          json_cell(c.get("inputs") or {}),json_cell(c["expected"])])
            if has_options:
                options = c.get("expected_any") or []
                cells.append(json_cell(options) if options else "—")
            cells.extend(["全部输出" if c.get("expect_full") else "列出字段",esc(c.get("note",""))])
            rows.append(cells)
        sections.append(table(headers,rows,"cases"))
    sections.append('<a class="end" href="#index">返回题目目录</a></article>')
    return "\n".join(sections)


def render():
    problems = [(json.loads(path.read_bytes()),path) for path in sorted(ROOT.glob("datasets/*/*-*.json"))]
    ids = [d["pid"] for d,_ in problems]
    if len(ids)!=35 or len(set(ids))!=len(ids):
        raise ValueError("Expected 35 distinct tasks")
    cases = sum(len(d["test_cases"]) for d,_ in problems)
    specs = [s for d,_ in problems for s in d["specs"]]
    ltl = sum(bool(s.get("ltl","").strip()) for s in specs)
    links = "".join(f'<li><a href="#{esc(quote(d["pid"],safe=""))}">{esc(d["pid"])} · {esc(d["title"])}</a></li>'
                    for d,_ in problems)
    parts = ['<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">',
             '<meta name="viewport" content="width=device-width,initial-scale=1">',
             '<title>STBench F1.4 题面与用例表</title><style>'+STYLE+'</style></head><body><main>',
             '<header><h1>STBench F1.4 题面与用例表</h1>',
             f'<p class="summary">{len(problems)} 题 · {cases} 条功能用例 · {ltl} 条 LTL · {len(specs)-ltl} 条无 LTL 的性质</p>',
             '<p><a href="sources/课程原题.json">课程公共题来源</a> · <a href="sources/index.json">来源索引</a> · '
             '<a href="evidence/full_run.json">逐组功能评分</a></p>',
             '<p>每条用例在指定拍数后计分一次。连续序列内保留内部状态，不同组从新实例开始。'
             '每条先写预置，再写常量和显式输入。未赋值的普通布尔输入归零，其他普通输入沿用当前值。'
             '提供 <code>scan_interval_ms</code> 的用例按表中毫秒时钟运行，新实例首次带时钟的调用从 0 ms 开始。'
             '<code>expected</code> 中的每个字段都要满足。有 <code>expected_any</code> 时，还须完整满足其中一组允许值。'
             '<code>$prefix</code> 检查数组的有效前缀。</p></header>',
             '<nav id="index" aria-label="题目目录"><h2>题目目录</h2><ul class="index">'+links+'</ul></nav>']
    parts.extend(render_problem(data,path) for data,path in problems)
    parts.append('</main></body></html>\n')
    return "\n".join(parts).encode("utf-8")


if __name__=="__main__":
    cli=argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--check-frozen",action="store_true",help="compare bytes without writing")
    args=cli.parse_args()
    result=render()
    if args.check_frozen:
        if not OUTPUT.is_file() or OUTPUT.read_bytes()!=result:
            raise SystemExit("Catalogue differs from current dataset rendering")
        print("Offline catalogue matches all 35 dataset files")
    else:
        OUTPUT.write_bytes(result)
        print("Wrote",OUTPUT.name,len(result),"bytes")

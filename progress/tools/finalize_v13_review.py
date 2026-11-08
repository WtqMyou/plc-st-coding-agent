"""Bind offline acceptance evidence and produce the standalone rereview material."""
from pathlib import Path
import html
import json
import subprocess
import sys

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO/'progress/v13'))
import revision as v
from stbench.platforms import CodesysBackend, OpenPLCBackend


def load(path): return json.loads(path.read_text('utf-8'))
def write(path, data): path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def main():
    out = REPO/'progress/evidence/v13_review_20261108'
    assert not (v.ROOT/'snapshot_manifest.json').exists(), 'Already frozen; use a new revision for further edits'
    subprocess.run([sys.executable, '-B', '-X', 'utf8', str(REPO/'progress/tools/build_v13_review.py')], check=True)
    tests = subprocess.run([sys.executable, '-B', '-X', 'utf8', '-m', 'unittest', 'discover', '-s', 'progress/tests', '-p', 'test_v13_review.py', '-q'],
        cwd=REPO, capture_output=True, text=True, encoding='utf-8')
    (out/'revision_tests.log').write_text(tests.stdout+'\n'+tests.stderr, encoding='utf-8')
    assert tests.returncode == 0
    old_log = (out/'frozen_engine_regression.log').read_text('utf-8')
    assert 'Ran 185 tests' in old_log and 'OK' in old_log
    offline = load(out/'offline.json')
    assert offline['passed'] and offline['cases_passed'] == offline['cases'] == 531
    assert (offline['raw_ltl'], offline['runtime_ltl'], offline['total_properties']) == (192,196,220)
    cfg = load(v.ENGINE/'config.example.json')
    for cls in (CodesysBackend, OpenPLCBackend):
        backend = cls(cfg)
        rows = load(out/(backend.name+'_references.json'))
        controls = load(out/(backend.name+'_controls.json'))
        assert len(rows) == 35 and controls['passed']
        for p in v.problems():
            q, code, _ = v.adapt(p, platform=backend.name)
            row = next(r for r in rows if r['pid'] == p.pid)
            assert row['status'] == 'passed' and row['source_sha256'] == v.digest(code.encode())
            assert row['platform_identity'] == backend.identity()
    upstream = load(v.ROOT/'upstream_manifest.json')
    for name, expected in upstream['files'].items():
        assert v.digest((v.ROOT/'upstream'/name).read_bytes()) == expected
    for path in (v.ROOT/'datasets/public').glob('public-*.json'):
        assert path.read_bytes() == (v.ROOT/'upstream/public'/path.name).read_bytes()
    budget = (REPO/'progress/evidence/review_20261108/audit_verified.json')
    assert load(budget)['ledger']['sha256'] == v.digest(Path('E:/PLC_Dev/evidence/dmxapi_budget_75.json').read_bytes())
    rescore = load(REPO/'progress/evidence/v13_rescore_20261108b/rescore.json')
    assert len(rescore['details']) == 140 and rescore['ledger_unchanged']
    for row in rescore['details']:
        candidate = REPO/'progress/evidence/v13_rescore_20261108b/candidates'/row['group']/(row['pid']+'.st')
        if candidate.is_file():
            assert v.digest(candidate.read_bytes()) == row['code_sha256']
    sections = []
    for p in v.problems():
        if p.pid not in v.FIVE: continue
        q, code, _ = v.adapt(p)
        sections.append(f'<section id="{html.escape(p.pid)}"><h2>{html.escape(p.pid+" · "+p.title)}</h2>'+
            '<h3>修订题面</h3><pre>'+html.escape(p.requirements)+'</pre><h3>原始接口</h3><pre>'+
            html.escape(json.dumps([x.to_dict() for x in p.variables], ensure_ascii=False, indent=2))+
            '</pre><h3>平台适配后参考 ST</h3><pre>'+html.escape(code)+'</pre><h3>全部用例</h3><pre>'+
            html.escape(json.dumps([x.to_dict() for x in q.test_cases], ensure_ascii=False, indent=2))+
            '</pre><h3>运行期性质</h3><pre>'+html.escape(json.dumps([x.to_dict() for x in q.specs], ensure_ascii=False, indent=2))+'</pre></section>')
    document = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>v1.3-review-r1 修改后复审材料</title><style>body{font:16px/1.7 system-ui,"Microsoft YaHei",sans-serif;margin:0;background:#f3f6fa;color:#203047}main{max-width:1100px;margin:auto;padding:25px}section{background:white;padding:22px;margin:22px 0;border-radius:12px}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f5f7fa;padding:14px;font:13px/1.7 Consolas,monospace}a{color:#155eab}</style><main>
<h1>v1.3-review-r1 修改后复审材料</h1><p>负责人刘晏铭；原结论五题均需修改。本材料用于修改后复审，尚未标为通过。</p>
<p>自动验收：531/531 功能用例、严格接口通过；CODESYS/OpenPLC 参考解各35/35。公式仅在给定测试序列上复验，不代表穷尽证明或实际装置验收。</p>
<p>原始接口 dt 在平台适配时统一改名 scanSeconds，秒单位和算法不变。请填写同目录“复审记录.md”的实际结论、问题、姓名与日期。</p>'''+''.join(sections)+'</main></html>'
    (v.ROOT/'复审材料.html').write_text(document, encoding='utf-8')
    acceptance = dict(version=v.VERSION, technical_passed=True, engine_sha256=v.ENGINE_SHA256,
        revised_tests=11, frozen_engine_regression_tests=185, reference_tasks=35, cases_passed=531, cases_total=531,
        codesys_references_passed=35, openplc_references_passed=35, native_positive_negative_controls_passed=True,
        original_ltl=192, runtime_ltl=196, simulation_only_runtime=24, total_properties=220,
        formula_scope='Given five reference test sequences; no exhaustive model-check claim',
        posthoc_records=140, posthoc_tool_unresolved=1, model_calls=0, ledger_unchanged=True,
        spent_cny=37.756189, ledger_events=423, human_review='corrected_pending_rereview',
        shared_engine_and_historical_data_changed=False, public_json_byte_identical=True)
    write(out/'acceptance.json', acceptance)
    files = [p for p in v.ROOT.rglob('*') if p.is_file() and '__pycache__' not in p.parts]
    files += [REPO/'progress/tools'/n for n in ['build_v13_review.py','validate_v13_review.py','rescore_v13_review.py','finalize_v13_review.py']]
    files += [REPO/'progress/tests/test_v13_review.py']
    reference_files = {str((v.ROOT/'references'/(p.pid+'.reference.st')).relative_to(REPO)) if (v.ROOT/'references'/(p.pid+'.reference.st')).is_file()
                       else str((v.ENGINE/'datasets'/p.source/'tests'/(p.pid+'.reference.st')).relative_to(REPO)) for p in v.problems()}
    manifest = dict(version=v.VERSION, engine_sha256=v.ENGINE_SHA256, human_review='corrected_pending_rereview',
        files={p.relative_to(REPO).as_posix():v.digest(p.read_bytes()) for p in sorted(set(files))},
        canonical_reference_dependencies={Path(n).as_posix():v.digest((REPO/n).read_bytes()) for n in sorted(reference_files)},
        acceptance_sha256=v.digest((out/'acceptance.json').read_bytes()))
    write(v.ROOT/'snapshot_manifest.json', manifest)
    print(json.dumps(acceptance, ensure_ascii=False))


if __name__ == '__main__': main()

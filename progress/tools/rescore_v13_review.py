"""Post-hoc scoring of fixed R8 candidates; no candidate selection or model calls."""
from pathlib import Path
import argparse
import hashlib
import json
import sys

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO/'progress/v13'))
import revision as v
from stbench.schema import Problem
from stbench.portability import adapt as old_adapt
from stbench.evaluation import local_tests, atomic_json
from stbench.st.driver import StageResult


def score(code, problem):
    try:
        return local_tests(code, problem), ''
    except Exception as exc:
        message = f'{type(exc).__name__}: {exc}'
        # Unresolved evaluator failures stay in the denominator, separately
        # labeled; never convert one into a proven model defect.
        return StageResult(compiles=False, tests_total=len(problem.test_cases),
                           failure_summary='Post-hoc evaluator error: '+message), message


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', type=Path, required=True)
    args = ap.parse_args()
    assert not args.out.exists(), 'Use a new output directory'
    args.out.mkdir(parents=True)
    ledger = Path('E:/PLC_Dev/evidence/dmxapi_budget_75.json')
    ledger_before = v.digest(ledger.read_bytes())
    source = Path('E:/PLC_Dev/evidence/real_experiments/campaign_75_window_r8/final')
    groups = ['custom_deepseek-v4pro', 'codex_deepseek-v4pro', 'custom_minimax-m27', 'codex_minimax-m27']
    rows, details = [], []
    all_problems = v.problems()
    for group in groups:
        row = dict(group=group, tasks=35, old_cases=435, new_cases=531, old_passed=0, new_passed=0,
                   old_solved=0, new_solved=0, lost=[], gained=[], missing_code=[], tool_errors=[])
        for new in all_problems:
            path = source/group/(new.pid+'.json')
            raw = path.read_bytes()
            record = json.loads(raw)
            attempts = record.get('attempts', [])
            index = record.get('best_attempt')
            assert index is None or isinstance(index, int) and 0 <= index < len(attempts), (group, new.pid, index)
            selected = attempts[index] if index is not None else None
            code = selected.get('code', '') if selected else ''
            old = Problem.load(v.ENGINE/'datasets'/new.source/(new.pid+'.json'))
            oq, _, _ = old_adapt(old, v.reference(old), 'codesys')
            nq, _, _ = v.adapt(new)
            # Score exactly the saved candidate, never adapt or repair its code.
            old_result, old_error = score(code, oq) if code else (None, '')
            new_result, new_error = score(code, nq) if code else (None, '')
            if old_error or new_error:
                row['tool_errors'].append(new.pid)
            old_ok = bool(old_result and old_result.compiles and old_result.all_tests_passed)
            new_ok = bool(new_result and new_result.compiles and new_result.all_tests_passed)
            row['old_passed'] += old_result.tests_passed if old_result else 0
            row['new_passed'] += new_result.tests_passed if new_result else 0
            row['old_solved'] += int(old_ok)
            row['new_solved'] += int(new_ok)
            if old_ok and not new_ok: row['lost'].append(new.pid)
            if new_ok and not old_ok: row['gained'].append(new.pid)
            if not code: row['missing_code'].append(new.pid)
            if code:
                candidate = args.out/'candidates'/group/(new.pid+'.st')
                candidate.parent.mkdir(parents=True, exist_ok=True)
                candidate.write_bytes(code.encode('utf-8'))
            details.append(dict(group=group, pid=new.pid, original_record=str(path), original_record_sha256=v.digest(raw),
                frozen_attempt_index=index, code_sha256=v.digest(code.encode()), original_reported_tests_passed=selected.get('tests_passed',0) if selected else 0,
                original_prompt_version=record.get('prompt_version'), old_local=old_result.to_dict() if old_result else None,
                new_local=new_result.to_dict() if new_result else None, old_solved=old_ok, new_solved=new_ok,
                old_evaluator_error=old_error, new_evaluator_error=new_error))
        rows.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)
    assert v.digest(ledger.read_bytes()) == ledger_before
    result = dict(version=v.VERSION, model_calls=0, ledger_unchanged=True, rows=rows, details=details,
        selection='Saved R8 best_attempt index, fixed before re-scoring; no new selection',
        scope='Post-hoc local functional scoring, same frozen stage-3 interpreter for both data versions. Native compilation and exhaustive model checks are not rerun for model candidates. Not a fresh v1.3 model experiment.')
    atomic_json(args.out/'rescore.json', result)
    lines = ['# 固定 R8 候选在修订题库上的事后评分', '', result['scope'], '',
        '| 组别 | 旧版本地功能整题 | 修订版本地功能整题 | 旧版通过用例 | 修订版通过用例 | 新失去通过题 | 工具异常题数 |',
        '| --- | ---: | ---: | ---: | ---: | --- | ---: |']
    for r in rows:
        lines.append(f'| {r["group"]} | {r["old_solved"]}/35 | {r["new_solved"]}/35 | {r["old_passed"]}/435 | {r["new_passed"]}/531 | {", ".join(r["lost"]) or "无"} | {len(r["tool_errors"])} |')
    lines += ['', '两侧使用相同本地检查器；候选由历史记录的 best_attempt 固定，未根据新版分数重新选择。缺失代码保留在35题分母。',
              '工具异常的题次保留在分母、单独标为未决，不能解释为已确认的模型错误。两侧通过数为已确认通过的数量。',
              '这些数值不替换 R8 正式结果；新数据不能弥补旧提示缺少新增需求的事实，也不能据此声称模型在新版生成实验中的能力。未新增模型费用。']
    (args.out/'重评分结果.md').write_text('\n'.join(lines)+'\n', encoding='utf-8')


if __name__ == '__main__': main()

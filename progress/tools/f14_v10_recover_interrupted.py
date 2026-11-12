"""One-time, evidence-preserving recovery for the interrupted V10 run.

It never sends a model request.  It reconciles the one locally captured, valid
upstream reply whose response-file write raised PermissionError before normal
settlement, then closes the three in-flight jobs without replaying any request.
"""
import copy
import hashlib
import json
from pathlib import Path
import sys

import f14_v10_core as s
from f14_v10_budget import HISTORY, KIND, money
from stbench.billing import ledger_lock
from stbench.transport import validate_response


def main():
    cfg = s.config()
    root = Path(cfg['campaign_root'])
    plan = s.load(root / 'study_plan.json')
    recovery = root / 'recovery_permissionerror_20261113'
    assert not recovery.exists(), 'Recovery evidence already exists'
    recovery.mkdir()

    condition = 'codex_minimax-m27'
    pid = 'public-easy-01'
    folder = root / 'jobs' / condition
    record_path = folder / (pid + '.json')
    record = s.load(record_path)
    assert record['job_done'] is False and len(record['attempts']) == 3
    raw = s.load(folder / (pid + '.response_03.json'))['raw_response']
    model = next(row for row in cfg['models'] if row['id'] == 'minimax-m27')
    checked = validate_response(raw, 'chat', model['accepted_models'])
    assert checked['complete'] and checked['text'].strip()
    cost = money((checked['prompt_tokens'] * model['input_cny_per_million'] +
                  checked['completion_tokens'] * model['output_cny_per_million']) / 1_000_000)

    source, edits = s.normalize(s.extract_code(checked['text']))
    result = s.evaluate(source, pid, cfg, __import__('time').monotonic() + 600)
    attempt = s.classify(result)
    attempt.update(idx=2, code=source, code_hash=hashlib.sha256(source.encode()).hexdigest(),
                   engineering_contract=s.compliance(source), actual_model=checked['model'],
                   prompt_tokens=checked['prompt_tokens'], completion_tokens=checked['completion_tokens'],
                   cost_cny=float(cost), latency_s=None, generation_seconds=None,
                   end_to_end_seconds=None, format_edits=edits,
                   raw_source_sha256=hashlib.sha256(s.extract_code(checked['text']).encode()).hexdigest(),
                   provider_error='')
    (folder / (pid + '.raw_candidate_03.st')).write_text(s.extract_code(checked['text']), encoding='utf-8')
    (folder / (pid + '.candidate_03.st')).write_text(source, encoding='utf-8')
    record['attempts'][2] = attempt
    record.update(job_done=True, stop_reason='recovered_captured_response_after_permissionerror',
                  error='', best_attempt=s.select_best(record['attempts']), finished_at=s.stamp())
    s.atomic_json(record_path, record)

    closed = [condition + '/' + pid]
    for other_condition, other_pid in [
        ('codex_deepseek-v4pro', 'public-easy-01'),
        ('codex_minimax-m27', 'public-easy-02'),
    ]:
        path = root / 'jobs' / other_condition / (other_pid + '.json')
        row = s.load(path)
        assert row['job_done'] is False and row['attempts']
        row.update(job_done=True, stop_reason='interrupted_after_recorded_candidates_no_replay',
                   error='', best_attempt=s.select_best(row['attempts']), finished_at=s.stamp())
        s.atomic_json(path, row)
        closed.append(other_condition + '/' + other_pid)

    ledger_path = Path(cfg['budget_ledger_path'])
    with ledger_lock(ledger_path):
        ledger = s.load(ledger_path)
        event = next(e for e in ledger['events'][HISTORY:]
                     if e['request']['job_id'] == condition + '/' + pid and e['request']['candidate_index'] == 2)
        assert event['status'] == 'reserved' and money(event['reserved_cny']) >= cost
        ledger['spent_cny'] = float(money(ledger['spent_cny']) - money(event['reserved_cny']) + cost)
        event.update(status='settled', accounted_cny=float(cost), metadata=dict(
            model=checked['model'], prompt_tokens=checked['prompt_tokens'],
            completion_tokens=checked['completion_tokens'], finish_reason=checked['finish_reason'],
            protocol='chat', recovery='captured_response_reconciled_after_local_permissionerror'))
        assert ledger.get('halted') == 'Malformed upstream result; reservation retained'
        ledger['halted'] = ''
        ledger['recoveries'].append(dict(kind=KIND, reason='local_response_capture_permissionerror',
            no_model_request_sent=True, recovered_job=condition + '/' + pid, candidate_index=2,
            response_sha256=s.sha(folder / (pid + '.response_03.json')), reconciled_cost_cny=float(cost),
            closed_jobs=closed, at=s.stamp()))
        s.atomic_json(ledger_path, ledger)

    s.atomic_json(recovery / 'recovery.json', dict(kind=KIND, cause='local response-evidence write PermissionError after a valid HTTP 200 response; not a model or network failure',
        no_model_request_sent=True, reconciled_job=condition + '/' + pid, reconciled_cost_cny=float(cost),
        closed_jobs=closed, response_sha256=s.sha(folder / (pid + '.response_03.json')), at=s.stamp()))
    s.atomic_json(root / 'ledger_checkpoint.json', dict(sha256=s.sha(ledger_path), at=s.stamp()))
    print('RECOVERED', json.dumps(dict(cost=float(cost), closed_jobs=closed), ensure_ascii=False))


if __name__ == '__main__':
    main()

"""Recover this diagnosed short task-tail timeout once; retain all unknown charges."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from stbench.billing import CampaignBudget, canonical_ledger, ledger_lock
from stbench.campaign import configuration, digest
from stbench.evaluation import atomic_json


def validate_failure(record, event, details, cfg, proof):
    attempts = record.get('attempts', [])
    task_seconds = cfg['limits']['task_seconds']
    request_seconds = cfg['limits']['request_seconds']
    window = request_seconds + cfg['limits']['codex_overhead_seconds']
    required = ('full_request_window', 'request_window_keeps_best', 'genuine_timeout_keeps_halt')
    if (proof.get('passed') is not True or proof.get('source_sha256') != digest() or
            proof.get('request_window_seconds') != window or
            not all(proof.get('deadline_checks', {}).get(k) is True for k in required)):
        raise RuntimeError('Current request-window and unknown-cost safety validation is required')
    if not attempts or len(attempts) < 2:
        raise RuntimeError('A short task-tail failure after earlier attempts is required')
    last = attempts[-1]
    timeout = event.get('request', {}).get('timeout_seconds', 0)
    before = sum(a.get('latency_s', 0) for a in attempts[:-1])
    total = sum(a.get('latency_s', 0) for a in attempts)
    error = 'Upstream wall deadline exceeded; no automatic retry'
    if (record.get('experiment_kind') != 'live' or record.get('stop_reason') != 'provider_error' or
            record.get('error') != error or last.get('provider_error') != error or
            last.get('code') or last.get('actual_model') or last.get('prompt_tokens') or last.get('completion_tokens') or
            event.get('status') != 'reserved' or event.get('phase') != 'development' or
            details.get('category') != 'request_timeout' or details.get('model') != record.get('model') or
            event.get('request', {}).get('model') != record.get('model') or
            not 0 < timeout < request_seconds or not 0 < task_seconds - before < window or
            abs(task_seconds - before - timeout) > 2 or abs(total - task_seconds) > 2 or
            last.get('latency_s', 0) < timeout - 1 or
            not record.get('started_at', float('inf')) <= event.get('created_at', 0) <= record.get('finished_at', 0)):
        raise RuntimeError('Failure does not identify the diagnosed local task-tail timeout')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--failure', type=Path, required=True)
    ap.add_argument('--validation', type=Path, required=True)
    args = ap.parse_args()
    cfg = configuration('')
    raw = args.failure.read_bytes()
    proof_raw = args.validation.read_bytes()
    record, proof = json.loads(raw), json.loads(proof_raw)
    ledger = canonical_ledger(cfg)
    with ledger_lock(ledger):
        budget = CampaignBudget(ledger, 'development', phase_caps=cfg['phase_limits'])
        state = budget.read(allow_halted=True)
        if state.get('halted') != 'Unconfirmed upstream result; reservation retained' or not state['events']:
            raise RuntimeError('An exact unknown-result halt is required')
        index = len(state['events']) - 1
        event = state['events'][index]
        details = state.get('halt_details', {})
        if details.get('event_index') != index or any(
                r.get('request_id') == event.get('request_id') for r in state.get('recoveries', [])):
            raise RuntimeError('This halted request is stale or already recovered')
        validate_failure(record, event, details, cfg, proof)
        backup = ledger.with_name(ledger.stem + '.before_request_window_recovery_' + uuid.uuid4().hex + '.json')
        with backup.open('xb') as out:
            out.write(ledger.read_bytes())
        recovery = dict(reason='validated_full_request_window_after_local_task_tail_timeout',
            previous_halt=state['halted'], request_id=event['request_id'],
            spent_cny_unchanged=state['spent_cny'], event_count_unchanged=len(state['events']),
            unknown_reservation_retained=event['reserved_cny'], backup=str(backup),
            failure=str(args.failure.resolve()), failure_sha256=hashlib.sha256(raw).hexdigest(),
            validation=str(args.validation.resolve()), validation_sha256=hashlib.sha256(proof_raw).hexdigest(),
            source_sha256=digest(), created_at=time.time())
        state.setdefault('recoveries', []).append(recovery)
        state['halted'] = ''
        state.pop('halt_details', None)
        atomic_json(ledger, state)
        atomic_json(Path(cfg['campaign_root']) / 'request_window_recovery.json', recovery)
    print(json.dumps(recovery, ensure_ascii=False))


if __name__ == '__main__':
    main()

"""One explicit continuation after a full timeout; retain its charge and do not retry it."""
import argparse
import ctypes
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from stbench import campaign
from stbench.billing import CampaignBudget, canonical_ledger, ledger_lock
from stbench.evaluation import atomic_json
from campaign_status import load, registered_process_alive, write_status
from resume_user_paused_campaign import current_process_marker, execute_remaining, validate_frozen_final


ERROR = 'Upstream wall deadline exceeded; no automatic retry'


def state_hash(state):
    return hashlib.sha256(json.dumps(state, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def validate_timeout(state, record, timing, cfg, plan):
    events = state.get('events', [])
    event = events[-1] if events else {}
    details = state.get('halt_details', {})
    attempts = record.get('attempts', [])
    attempt = attempts[0] if len(attempts) == 1 else {}
    request = event.get('request', {})
    limit = cfg['limits']['request_seconds']
    window = limit + cfg['limits']['codex_overhead_seconds']
    elapsed = max(record.get('total_latency_s', 0), timing.get('active_wall_seconds', 0))
    if (plan.get('action') != 'explicit_continue_remaining_after_full_timeout' or
            state.get('version') != 3 or state.get('limit_cny') != 75 or
            state.get('halted') != 'Unconfirmed upstream result; reservation retained' or
            state_hash(state) != plan.get('ledger_state_sha256') or
            details.get('category') != 'request_timeout' or details.get('event_index') != len(events) - 1 or
            len(events) != plan.get('event_count') or state.get('spent_cny') != plan.get('spent_cny') or
            event.get('request_id') != plan.get('request_id') or not event.get('request_id') or
            event.get('status') != 'reserved' or event.get('phase') != 'final' or
            request.get('timeout_seconds') != limit or limit != 420 or window != 450 or
            request.get('max_output_tokens') != cfg['limits']['max_output_tokens'] or
            request.get('model') != record.get('model') or details.get('model') != record.get('model') or
            details.get('protocol') != request.get('protocol') or
            record.get('model') not in campaign.EXPECTED_MODELS or record.get('provider') != 'codex-cli' or
            record.get('experiment_kind') != 'live' or record.get('stop_reason') != 'provider_error' or
            record.get('error') != ERROR or record.get('request_window_seconds') != window or
            len(attempts) != 1 or attempt.get('provider_error') != ERROR or
            attempt.get('code') or attempt.get('actual_model') or attempt.get('prompt_tokens') or
            attempt.get('completion_tokens') or attempt.get('cost_cny') or
            not record.get('started_at', float('inf')) <= event.get('created_at', 0) <= record.get('finished_at', 0) or
            not limit - 1 <= record.get('finished_at', 0) - event.get('created_at', 0) <= window + 2 or
            not 0 <= cfg['limits']['task_seconds'] - elapsed < window or
            attempt.get('latency_s', 0) < limit - 1 or
            any(r.get('request_id') == event.get('request_id') for r in state.get('recoveries', []))):
        raise RuntimeError('This plan does not identify the unchanged full-window timeout; no recovery applied')


def validate_checkpoint(cfg, plan, validation):
    root = Path(cfg['campaign_root']).resolve()
    if plan.get('campaign_root') != str(root) or plan.get('source_sha256') != campaign.digest():
        raise RuntimeError('Continuation plan source or campaign mismatch')
    selected = validate_frozen_final(cfg, validation, plan.get('selected_configuration_sha256'))
    proof = load(plan['repair_validation'])
    if proof.get('passed') is not True or proof.get('source_sha256') != campaign.digest():
        raise RuntimeError('Passing accounting and timeout continuation checks are required')
    required = {'scripts/resume_final_after_timeout.py', 'scripts/resume_user_paused_campaign.py',
                'scripts/request_accounting.py', 'scripts/analyze_campaign.py'}
    if not required <= proof.get('files', {}).keys():
        raise RuntimeError('Repair validation does not identify all changed scripts')
    for name, expected in proof['files'].items():
        if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != expected:
            raise RuntimeError('Repair scripts changed after validation: ' + name)
    failure = (root / plan['failure_relative_path']).resolve()
    if root / 'final' not in failure.parents or hashlib.sha256(failure.read_bytes()).hexdigest() != plan['failure_sha256']:
        raise RuntimeError('Timeout record changed or is outside this final stage')
    record = load(failure)
    spec = next((m for m in cfg['models'] if m['model'] == record.get('model')), None)
    if not spec or failure != root / 'final' / ('codex_' + spec['id']) / (record['pid'] + '.json'):
        raise RuntimeError('Failure record is not the planned Codex/model/task condition')
    timing_path = failure.with_name(failure.stem + '.timing.json')
    if hashlib.sha256(timing_path.read_bytes()).hexdigest() != plan['timing_sha256']:
        raise RuntimeError('Timeout active time changed')
    count = sum(bool(load(p).get('attempts')) for p in (root / 'final').glob('*/*.json')
                if not p.name.endswith(('.timing.json', '.openplc.json')))
    if count != plan['final_attempted'] or (root / 'campaign_completion.json').exists():
        raise RuntimeError('Formal progress changed or already completed')
    ledger = canonical_ledger(cfg)
    with ledger_lock(ledger):
        state = CampaignBudget(ledger, 'final', phase_caps=cfg['phase_limits']).read(allow_halted=True)
        validate_timeout(state, record, load(timing_path), selected, plan)
        if any(registered_process_alive(load(root / name)) for name in ('active_run.json', 'collector_run.json')):
            raise RuntimeError('A registered runner or collector is already alive')
    return selected, failure, record


def release_timeout(cfg, plan, record, timing, history, marker):
    root = Path(cfg['campaign_root'])
    ledger = canonical_ledger(cfg)
    with ledger_lock(ledger):
        state = CampaignBudget(ledger, 'final', phase_caps=cfg['phase_limits']).read(allow_halted=True)
        validate_timeout(state, record, timing, cfg, plan)
        if any(registered_process_alive(load(root / name)) for name in ('active_run.json', 'collector_run.json')):
            raise RuntimeError('Duplicate runner or collector refused')
        with (history / 'ledger_before_resume.json').open('xb') as out:
            out.write(ledger.read_bytes())
        receipt = dict(reason='explicit_user_continue_remaining_after_full_timeout_no_retry',
            request_id=plan['request_id'], previous_halt=state['halted'],
            spent_cny_unchanged=state['spent_cny'], event_count_unchanged=len(state['events']),
            current_reservation_retained=state['events'][-1]['reserved_cny'],
            all_unknown_reservations_retained=sum(e['reserved_cny'] for e in state['events'] if e['status'] == 'reserved'),
            source_sha256=campaign.digest(), backup=str(history / 'ledger_before_resume.json'),
            created_at=time.time(), notice='Only this diagnosed halt cleared; future unknown results still halt')
        state.setdefault('recoveries', []).append(receipt)
        state['halted'] = ''
        state.pop('halt_details', None)
        atomic_json(history / 'resume_authorization.json', receipt)
        atomic_json(root / 'active_run.json', marker)
        atomic_json(root / 'runner_exit.json', dict(state='running', run_id=marker['run_id']))
        atomic_json(root / 'finish_status.json', dict(state='running', run_id=marker['run_id']))
        atomic_json(ledger, state)
    return receipt


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--plan', type=Path, required=True)
    ap.add_argument('--validation', type=Path, required=True)
    ap.add_argument('--check-only', action='store_true')
    ap.add_argument('--run-id', default='')
    args = ap.parse_args()
    cfg = campaign.configuration('')
    plan = load(args.plan)
    selected, failure, record = validate_checkpoint(cfg, plan, args.validation)
    if args.check_only:
        print(json.dumps(dict(passed=True, final_attempted=plan['final_attempted'],
            remaining=140 - plan['final_attempted'], spent_cny=plan['spent_cny'],
            timeout_will_not_retry=True, generation_requests=0)), flush=True)
        return 0
    if os.name != 'nt':
        raise RuntimeError('This validated native campaign requires Windows')
    catalog = campaign.credential_check(selected)
    if not all(catalog['selected_models'].values()):
        raise RuntimeError('Selected models absent from authenticated catalog; no generation request sent')
    run_id = args.run_id or uuid.uuid4().hex
    if not run_id.isalnum():
        raise RuntimeError('Resume run id must be alphanumeric')
    root = Path(cfg['campaign_root'])
    history = root / 'resume_history' / run_id
    history.mkdir(parents=True, exist_ok=False)
    for name in ('active_run.json', 'collector_run.json', 'runner_exit.json', 'finish_status.json',
                 'execution_state.json', 'selected_configuration.json'):
        path = root / name
        if path.exists():
            with (history / name).open('xb') as out:
                out.write(path.read_bytes())
    with zipfile.ZipFile(history / 'formal_before_resume.zip', 'x', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted((root / 'final').rglob('*')):
            if path.is_file():
                archive.write(path, path.relative_to(root).as_posix())
    atomic_json(history / 'plan.json', plan)
    atomic_json(history / 'credential_check.json', catalog)
    atomic_json(history / 'repair_validation.json', load(plan['repair_validation']))
    atomic_json(history / 'core_validation.json', load(args.validation))
    test_log = Path(plan['repair_validation']).parent / 'unit_tests_final.log'
    with (history / 'repair_unit_tests.log').open('xb') as out:
        out.write(test_log.read_bytes())
    marker = dict(**current_process_marker(), run_id=run_id, state='running', entry='resume_final_after_timeout.py',
        source_sha256=campaign.digest(), timeout_request_id=plan['request_id'], resume_stage='final',
        total_authorized_cny=75, ledger=str(canonical_ledger(cfg)), history=str(history))
    timing = load(failure.with_name(failure.stem + '.timing.json'))
    release_timeout(selected, plan, record, timing, history, marker)
    awake = False
    try:
        awake = bool(ctypes.windll.kernel32.SetThreadExecutionState(0x80000001))
        atomic_json(root / 'execution_state.json', dict(system_awake_requested=awake,
            display_awake_requested=False, state='active', run_id=run_id))
        write_status(root, cfg)
        print(f"Continuing remaining {140-plan['final_attempted']} formal jobs; timeout and all charges retained", flush=True)
        execute_remaining(selected, dict(timeout_request_id=plan['request_id']), history)
    except BaseException as error:
        atomic_json(root / 'runner_exit.json', dict(state='stopped', run_id=run_id,
            error_type=type(error).__name__, error=str(error), at=datetime.now(timezone.utc).isoformat(),
            source_sha256=campaign.digest()))
        raise
    else:
        atomic_json(root / 'runner_exit.json', dict(state='completed', run_id=run_id, returncode=0,
            at=datetime.now(timezone.utc).isoformat(), source_sha256=campaign.digest()))
    finally:
        if awake:
            ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
        atomic_json(root / 'execution_state.json', dict(system_awake_requested=awake,
            display_awake_requested=False, state='released', run_id=run_id))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

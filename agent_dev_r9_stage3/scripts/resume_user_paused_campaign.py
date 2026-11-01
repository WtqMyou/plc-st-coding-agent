"""Resume an explicitly user-paused final stage without replaying development."""
import argparse
import copy
import ctypes
from ctypes import wintypes
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
from stbench.platforms import CodesysBackend, OpenPLCBackend
from campaign_status import load, registered_process_alive, write_status


def validate_pause(state, pause, before, source):
    details = state.get('halt_details', {})
    events = state.get('events', [])
    last = events[-1] if events else {}
    if (state.get('version') != 3 or state.get('limit_cny') != 75 or
            pause.get('state') != 'paused' or pause.get('resume_stage') != 'final' or
            pause.get('source_sha256') != source or
            pause.get('runner_stopped') is not True or pause.get('collector_stopped') is not True or
            state.get('halted') != 'Paused by user for laptop relocation' or
            details.get('category') != 'user_pause' or not pause.get('pause_id') or
            details.get('pause_id') != pause['pause_id'] or
            state.get('spent_cny') != pause.get('spent_cny') or len(events) != pause.get('event_count') or
            last.get('request_id') != pause.get('last_request_id') or last.get('status') != 'settled' or
            pause.get('last_event_status') != 'settled' or
            any(r.get('pause_id') == pause['pause_id'] for r in state.get('recoveries', []))):
        raise RuntimeError('Only this unchanged, settled user pause can be resumed')
    strip_halt = lambda value: {k: v for k, v in value.items() if k not in ('halted', 'halt_details')}
    if before.get('halted') or strip_halt(state) != strip_halt(before):
        raise RuntimeError('Ledger history differs from the saved pause boundary')


def validate_frozen_final(cfg, validation, selected_sha256):
    root = Path(cfg['campaign_root'])
    proof = load(validation)
    source = campaign.digest()
    if proof.get('passed') is not True or proof.get('source_sha256') != source:
        raise RuntimeError('Current passing offline validation is required')
    selected_path = root / 'selected_configuration.json'
    if hashlib.sha256(selected_path.read_bytes()).hexdigest() != selected_sha256:
        raise RuntimeError('The selected development strategy changed after the pause')
    selected = campaign.configuration(str(selected_path))
    if {k: v for k, v in selected.items() if k != 'strategy'} != {k: v for k, v in cfg.items() if k != 'strategy'}:
        raise RuntimeError('Base campaign settings changed after the pause')
    routes = load(root / 'routes.json')
    frozen = load(root / 'final' / 'freeze.json')
    if not frozen or frozen != campaign.snapshot(selected, routes):
        raise RuntimeError('Final source, dataset, configuration or routes changed')
    with zipfile.ZipFile(root / 'frozen_source_before_campaign.zip') as archive:
        for name, expected in frozen['files'].items():
            if hashlib.sha256(archive.read(name)).hexdigest() != expected:
                raise RuntimeError('Original frozen archive differs: ' + name)
    if not campaign.limits_verified(selected, root):
        raise RuntimeError('Output-cap evidence is missing or stale')
    if not campaign.pilot_ready(selected, load(root / 'pilot' / 'summary.json')):
        raise RuntimeError('The four completed pilot conditions are required')
    native = load(root / 'native_preflight.json')
    for backend in (CodesysBackend(selected), OpenPLCBackend(selected)):
        row = native.get(backend.name, {})
        if (row.get('positive', {}).get('status') != 'passed' or
                row.get('negative', {}).get('status') != 'failed' or
                row['positive'].get('platform_identity') != backend.identity()):
            raise RuntimeError('Compiler control identity changed; no model request sent')
    return selected


def validate_checkpoint(cfg, validation):
    root = Path(cfg['campaign_root'])
    pause = load(root / 'user_pause.json')
    selected = validate_frozen_final(cfg, validation, pause.get('selected_configuration_sha256'))
    count = sum(bool(load(p).get('attempts')) for p in (root / 'final').glob('*/*.json')
                if not p.name.endswith(('.timing.json', '.openplc.json')))
    if count != pause.get('counts', {}).get('final') or (root / 'campaign_completion.json').exists():
        raise RuntimeError('Formal progress changed or the campaign already completed')
    ledger = canonical_ledger(cfg)
    with ledger_lock(ledger):
        state = CampaignBudget(ledger, 'final', phase_caps=cfg['phase_limits']).read(allow_halted=True)
        validate_pause(state, pause, load(pause['backup']), campaign.digest())
        for name in ('active_run.json', 'collector_run.json'):
            if registered_process_alive(load(root / name)):
                raise RuntimeError('A registered runner or collector is already alive')
    return selected, pause, count


def current_process_marker():
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.GetCurrentProcess.restype = wintypes.HANDLE
    kernel.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
    times = [wintypes.FILETIME() for _ in range(4)]
    if not kernel.GetProcessTimes(kernel.GetCurrentProcess(), *(ctypes.byref(t) for t in times)):
        raise OSError('Could not identify the runner creation time')
    ticks = (times[0].dwHighDateTime << 32) | times[0].dwLowDateTime
    return dict(pid=os.getpid(), process_created_at=datetime.fromtimestamp(
        ticks / 10000000 - 11644473600, timezone.utc).isoformat())


def release_pause(cfg, pause, history, marker):
    root = Path(cfg['campaign_root'])
    ledger = canonical_ledger(cfg)
    with ledger_lock(ledger):
        state = CampaignBudget(ledger, 'final', phase_caps=cfg['phase_limits']).read(allow_halted=True)
        validate_pause(state, pause, load(pause['backup']), campaign.digest())
        if any(registered_process_alive(load(root / name)) for name in ('active_run.json', 'collector_run.json')):
            raise RuntimeError('Duplicate runner or collector refused')
        with (history / 'ledger_before_resume.json').open('xb') as out:
            out.write(ledger.read_bytes())
        recovery = dict(reason='explicit_user_resume_after_relocation', pause_id=pause['pause_id'],
            spent_cny_unchanged=state['spent_cny'], event_count_unchanged=len(state['events']),
            unknown_reservations_retained=sum(e['reserved_cny'] for e in state['events'] if e['status'] == 'reserved'),
            backup=str(history / 'ledger_before_resume.json'), source_sha256=campaign.digest(), created_at=time.time())
        state.setdefault('recoveries', []).append(recovery)
        state['halted'] = ''
        state.pop('halt_details', None)
        atomic_json(history / 'resume_authorization.json', recovery)
        atomic_json(root / 'active_run.json', marker)
        atomic_json(root / 'runner_exit.json', dict(state='running', run_id=marker['run_id']))
        atomic_json(root / 'finish_status.json', dict(state='running', run_id=marker['run_id'],
                    previous_reports=load(history / 'finish_status.json').get('reports')))
        atomic_json(ledger, state)
    return recovery


def execute_remaining(selected, pause, history):
    root = Path(selected['campaign_root'])
    selected_path = root / 'selected_configuration.json'
    campaign.main(['final', '--live', '--config', str(selected_path)])
    rows = load(root / 'final' / 'summary.json')
    expected = set(campaign.group_order(selected))
    if (len(rows) != 4 or {(r.get('framework'), r.get('model_id')) for r in rows} != expected or
            any(r.get('n') != 35 or r.get('attempted') != 35 for r in rows)):
        raise RuntimeError('Formal coverage remains incomplete; retain partial results')
    if all(r['generated'] == 35 for r in rows):
        ablation = copy.deepcopy(selected)
        ablation['strategy']['include_ltl'] = False
        ablation_path = history / 'retest_configuration.json'
        atomic_json(ablation_path, ablation)
        try:
            campaign.main(['retest', '--live', '--config', str(ablation_path)])
        except campaign.ProviderError as error:
            if 'Budget' not in str(error) and 'first-candidate' not in str(error):
                raise
    budget = campaign.budget_for(selected, 'final').snapshot()
    atomic_json(root / 'campaign_completion.json', dict(final_conditions=len(rows),
        full_generation_coverage=all(r['generated'] == 35 for r in rows),
        custom_goal_reached=all(r['solve_rate'] == 1 for r in rows if r['framework'] == 'custom'),
        resumed_from_pause=pause.get('pause_id'), resumed_after_timeout=pause.get('timeout_request_id'), budget=budget))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--validation', type=Path, required=True)
    ap.add_argument('--check-only', action='store_true')
    ap.add_argument('--run-id', default='')
    args = ap.parse_args()
    cfg = campaign.configuration('')
    root = Path(cfg['campaign_root'])
    selected, pause, count = validate_checkpoint(cfg, args.validation)
    if args.check_only:
        print(json.dumps(dict(passed=True, final_attempted=count, spent_cny=pause['spent_cny'],
                              source_sha256=campaign.digest(), generation_requests=0)), flush=True)
        return 0
    if os.name != 'nt':
        raise RuntimeError('This validated native campaign requires Windows')
    catalog = campaign.credential_check(selected)
    if not all(catalog['selected_models'].values()):
        raise RuntimeError('Selected models absent from authenticated catalog; no generation request sent')
    run_id = args.run_id or uuid.uuid4().hex
    if not run_id.isalnum():
        raise RuntimeError('Resume run id must be alphanumeric')
    history = root / 'resume_history' / run_id
    history.mkdir(parents=True, exist_ok=False)
    for name in ('user_pause.json', 'active_run.json', 'collector_run.json', 'runner_exit.json',
                 'finish_status.json', 'execution_state.json', 'selected_configuration.json'):
        path = root / name
        if path.exists():
            with (history / name).open('xb') as out:
                out.write(path.read_bytes())
    with zipfile.ZipFile(history / 'formal_before_resume.zip', 'x', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted((root / 'final').rglob('*')):
            if path.is_file():
                archive.write(path, path.relative_to(root).as_posix())
    atomic_json(history / 'credential_check.json', catalog)
    marker = dict(**current_process_marker(), run_id=run_id, state='running',
        entry='resume_user_paused_campaign.py', source_sha256=campaign.digest(),
        resumed_from_pause=pause['pause_id'], resume_stage='final', total_authorized_cny=75,
        ledger=str(canonical_ledger(cfg)), history=str(history))
    release_pause(cfg, pause, history, marker)
    awake = False
    try:
        awake = bool(ctypes.windll.kernel32.SetThreadExecutionState(0x80000001))
        atomic_json(root / 'execution_state.json', dict(system_awake_requested=awake,
            display_awake_requested=False, state='active', run_id=run_id))
        write_status(root, cfg)
        print(f'Resuming frozen final stage: {count}/140 saved; total budget 75 CNY', flush=True)
        execute_remaining(selected, pause, history)
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

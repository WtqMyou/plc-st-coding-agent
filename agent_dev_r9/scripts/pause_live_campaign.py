"""Pause at a settled ledger boundary; never interrupt an in-flight settlement."""
import json
from pathlib import Path
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from stbench.billing import canonical_ledger, ledger_lock
from stbench.campaign import configuration, digest
from stbench.evaluation import atomic_json


def main():
    cfg = configuration('')
    root = Path(cfg['campaign_root'])
    ledger = canonical_ledger(cfg)
    requested = time.time()
    pause_id = uuid.uuid4().hex
    atomic_json(root / 'user_pause_request.json', dict(pause_id=pause_id, requested_at=requested,
                reason='User requested pause for laptop relocation'))
    deadline = time.monotonic() + cfg['limits']['request_seconds'] + cfg['limits']['codex_overhead_seconds'] + 30
    last_notice = 0
    while True:
        with ledger_lock(ledger):
            raw = ledger.read_bytes()
            state = json.loads(raw)
            event = state['events'][-1] if state['events'] else {}
            if state.get('halted'):
                record = dict(pause_id=pause_id, state='already_stopped', requested_at=requested,
                    stopped_at=time.time(), previous_halt=state['halted'], spent_cny=state['spent_cny'],
                    event_count=len(state['events']), source_sha256=digest(),
                    notice='Existing halt preserved; no charge refunded and no further requests permitted')
                atomic_json(root / 'user_pause.json', record)
                print(json.dumps(record, ensure_ascii=False), flush=True)
                return
            if not event or event.get('status') == 'settled':
                backup = ledger.with_name(ledger.stem + '.before_user_pause_' + pause_id + '.json')
                with backup.open('xb') as out:
                    out.write(raw)
                reason = 'Paused by user for laptop relocation'
                state['halted'] = reason
                state['halt_details'] = dict(category='user_pause', pause_id=pause_id, requested_at=requested)
                atomic_json(ledger, state)
                record = dict(pause_id=pause_id, state='pause_set', requested_at=requested, paused_at=time.time(),
                    reason=reason, spent_cny=state['spent_cny'], event_count=len(state['events']),
                    last_request_id=event.get('request_id'), last_event_status=event.get('status'),
                    source_sha256=digest(), backup=str(backup),
                    notice='Pause applied after settlement; all existing events and unknown reservations retained')
                atomic_json(root / 'user_pause.json', record)
                print(json.dumps(record, ensure_ascii=False), flush=True)
                return
        if time.monotonic() >= deadline:
            raise RuntimeError('Pause wait limit reached; inspect the still-running request before disconnecting')
        if time.monotonic() - last_notice >= 45:
            print('Waiting for the current request to settle; no in-flight request interrupted', flush=True)
            last_notice = time.monotonic()
        time.sleep(.05)


if __name__ == '__main__':
    main()

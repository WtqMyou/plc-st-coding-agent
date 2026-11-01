"""Resume an exact, operator-created maintenance pause without refunding any charge."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from stbench.billing import ledger_lock, canonical_ledger
from stbench.campaign import configuration, digest
from stbench.evaluation import atomic_json


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--pause', type=Path, required=True)
    ap.add_argument('--validation', type=Path, required=True)
    args = ap.parse_args()
    pause = json.loads(args.pause.read_text(encoding='utf-8'))
    validation_raw = args.validation.read_bytes()
    validation = json.loads(validation_raw)
    if validation.get('passed') is not True or validation.get('source_sha256') != digest():
        raise RuntimeError('Current source requires passing validation')
    ledger = canonical_ledger(configuration(''))
    with ledger_lock(ledger):
        raw = ledger.read_bytes()
        state = json.loads(raw)
        details = state.get('halt_details', {})
        if (state.get('halted') != pause['reason'] or
                details.get('category') != 'controlled_maintenance' or
                details.get('pause_id') != pause['pause_id'] or
                len(state['events']) != pause['event_count'] or
                state['spent_cny'] != pause['spent_cny'] or
                not state['events'] or state['events'][-1]['status'] != 'settled'):
            raise RuntimeError('Pause no longer identifies the exact settled maintenance state')
        backup = ledger.with_name(ledger.stem + '.before_maintenance_recovery_' + uuid.uuid4().hex + '.json')
        with backup.open('xb') as out:
            out.write(raw)
        recovery = dict(reason='validated_repair_coverage_guard', pause_id=pause['pause_id'],
                        previous_halt=state['halted'], spent_cny_unchanged=state['spent_cny'],
                        event_count_unchanged=len(state['events']), backup=str(backup),
                        pause=str(args.pause.resolve()), validation=str(args.validation.resolve()),
                        validation_sha256=hashlib.sha256(validation_raw).hexdigest(),
                        source_sha256=digest(), created_at=time.time())
        state.setdefault('recoveries', []).append(recovery)
        state['halted'] = ''
        state.pop('halt_details', None)
        atomic_json(ledger, state)
        atomic_json(Path(configuration('')['campaign_root']) / 'maintenance_recovery.json', recovery)
    print(json.dumps(recovery, ensure_ascii=False))


if __name__ == '__main__':
    main()

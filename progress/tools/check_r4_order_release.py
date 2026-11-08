"""Read-only validation of the final pilot publication and historical billing prefix."""
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import r4_check_order as study

cfg=study.configuration(str(study.CONFIG));root=Path(cfg['campaign_root'])
study.verify_frozen(root)
m=study.load(study.MIRROR/'release_manifest.json')
assert m==study.load(root/'release_manifest.json')
assert m['finalizer_sha256']==study.sha(study.REPO/'progress/tools/finalize_r4_check_order.py')
for name,expected in m['files'].items():
    assert study.sha(root/name)==expected,name
    assert study.sha(study.MIRROR/name)==expected,name
analysis=study.load(root/'analysis.json');native=study.load(root/'posthoc_native_boundary.json')
assert analysis['analyzer_sha256']==study.sha(study.REPO/'progress/tools/analyze_r4_check_order.py')
assert native['source_sha256']==study.sha(study.REPO/'progress/tools/audit_r4_order_boundaries.py')
plan=study.load(root/'study_plan.json');before=study.load(root/'ledger_before_study.json')
costs=study.load(root/'本轮费用明细.json');ledger=study.load(cfg['budget_ledger_path'])
n=plan['initial_event_count'];events=costs['events']
assert ledger['events'][:n]==before['events']
assert ledger['events'][n:n+len(events)]==events
assert len(events)==15 and all(e['status']=='settled' for e in events)
assert ledger.get('recoveries',[])[:len(before.get('recoveries',[]))]==before.get('recoveries',[])
assert study.load(root/'study_state.json')['state']=='completed'
print('PASS frozen pilot, r4, final publication hashes and original billing prefix')

"""Judge-only r3 revision: all data and candidate inputs stay frozen."""
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
PARENT = REPO/'progress/v13_r2'
VERSION = 'v1.3-judge-r3'
DATA_VERSION = 'v1.3-review-r2'


def digest(data): return hashlib.sha256(data).hexdigest()


def verify_parent():
    origin=json.loads((ROOT/'ORIGIN_R2.json').read_text('utf-8'))
    raw=(PARENT/'snapshot_manifest.json').read_bytes()
    if digest(raw)!=origin['parent_manifest_sha256']:raise RuntimeError('r2 manifest changed')
    m=json.loads(raw)
    for name,expected in {**m['files'],**m['evidence_sha256']}.items():
        if digest((REPO/name).read_bytes())!=expected:raise RuntimeError('r2 dependency changed: '+name)
    scores=REPO/'progress/evidence/v13_r2_rescore_20261108/rescore.json'
    if digest(scores.read_bytes())!=m['rescore_sha256']:raise RuntimeError('r2 fixed-candidate results changed')


verify_parent()
sys.path.insert(0,str(PARENT))
import r2_revision as r2
r2.verify_parent()
ENGINE, ENGINE_SHA256, FIVE = r2.ENGINE, r2.ENGINE_SHA256, r2.FIVE
problems, reference, adapt = r2.problems, r2.reference, r2.adapt


def historical_candidate():
    p=REPO/'progress/evidence/v13_rescore_20261108b/candidates/codex_minimax-m27/public-medium-08.st'
    raw=p.read_bytes()
    assert digest(raw)==json.loads((ROOT/'ORIGIN_R2.json').read_text('utf-8'))['candidate_sha256']
    return raw.decode('utf-8')

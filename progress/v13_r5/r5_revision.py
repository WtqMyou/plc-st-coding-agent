"""Judge-only r5: pin r4 data and the completed pilot without rewriting either."""
import hashlib
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parents[1]
PARENT=REPO/'progress/v13_r4'
VERSION='v1.3-judge-r5'
DATA_VERSION='v1.3-review-r4'


def digest(raw):return hashlib.sha256(raw).hexdigest()


def verify_parent():
    origin=json.loads((ROOT/'ORIGIN_R4.json').read_text('utf-8'))
    raw=(PARENT/'snapshot_manifest.json').read_bytes()
    assert digest(raw)==origin['parent_manifest_sha256'],'r4 manifest changed'
    m=json.loads(raw)
    for name,sha in {**m['files'],**m['evidence_sha256']}.items():
        assert digest((REPO/name).read_bytes())==sha,name
    scores=REPO/'progress/evidence/v13_r4_rescore_20261108b/rescore.json'
    assert digest(scores.read_bytes())==m['rescore_sha256']
    pilot=REPO/'progress/evidence/r4_check_order_20261108'
    raw=(pilot/'release_manifest.json').read_bytes()
    assert digest(raw)==origin['pilot_release_sha256'],'Pilot release changed'
    for name,sha in json.loads(raw)['files'].items():
        assert digest((pilot/name).read_bytes())==sha,name


verify_parent()
sys.path.insert(0,str(PARENT))
import r4_revision as r4
r4.verify_parent();r4.r3.r2.r1.verify_engine()
ENGINE=r4.ENGINE
problems,reference,adapt=r4.problems,r4.reference,r4.adapt

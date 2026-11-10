"""Audited November 10 data delta; the frozen r5 execution model is reused."""
import copy
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
VERSION = 'v1.3-review-r6'
JUDGE_VERSION = 'v1.3-judge-r5'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def verify_parent():
    origin = json.loads((ROOT/'ORIGIN_R5.json').read_text('utf-8'))
    parent = REPO/'progress/v13_r5/snapshot_manifest.json'
    assert digest(parent.read_bytes()) == origin['parent_manifest_sha256']
    manifest = json.loads(parent.read_bytes())
    for name, sha in {**manifest['files'], **manifest['evidence_sha256'],
                      **manifest['additional_proof_sha256']}.items():
        assert digest((REPO/name).read_bytes()) == sha, name
    assert digest((REPO/'progress/evidence/v13_r5_rescore_20261108b/rescore.json').read_bytes()) == manifest['rescore_sha256']


verify_parent()
sys.path.insert(0, str(REPO/'progress/v13_r5'))
import r5_revision as r5
r5.verify_parent()
ENGINE = r5.ENGINE
from stbench.schema import Problem


def problems():
    return [Problem.load(p) for p in sorted((ROOT/'datasets').glob('*/*.json'))]


def reference(problem):
    return (ROOT/'references'/(problem.pid+'.reference.st')).read_text('utf-8')


def adapt(problem, source=None, platform='codesys', mc_seconds=None):
    # These are already platform-adapted contracts; applying portability twice
    # would append a second FIFO capacity variable and corrupt its bindings.
    if platform not in ('codesys', 'openplc'):
        raise ValueError('Unsupported platform')
    p = copy.deepcopy(problem)
    if mc_seconds is not None:
        import math
        if isinstance(mc_seconds, bool) or not isinstance(mc_seconds, (float,int)) or not math.isfinite(mc_seconds) or mc_seconds <= 0:
            raise ValueError('MC budget must be finite and positive')
        p.mc_max_seconds = float(mc_seconds)
    mapping = copy.deepcopy(p.provenance['platform_adaptation'])
    mapping.update(platform=platform, data_version=VERSION, already_adapted=True)
    p.provenance['platform_adaptation'] = mapping
    return p, reference(p) if source is None else source, mapping

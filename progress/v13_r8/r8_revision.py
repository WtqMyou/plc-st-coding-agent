"""Apply lym's returned contracts in a new data revision over the frozen r7 judge."""
import copy
import hashlib
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parents[1]
VERSION='v1.3-review-r8'
JUDGE_VERSION='v1.3-judge-r7'
CONTRACT_CHANGED={'public-easy-04','self-hard-04','self-medium-03'}


def digest(raw):return hashlib.sha256(raw).hexdigest()


def verify_parent():
    origin=json.loads((ROOT/'ORIGIN_R7.json').read_text('utf-8'))
    parent=REPO/'progress/v13_r7/snapshot_manifest.json'
    assert digest(parent.read_bytes())==origin['parent_manifest_sha256']
    for name,sha in json.loads(parent.read_bytes())['files'].items():
        assert digest((REPO/name).read_bytes())==sha,name


verify_parent()
sys.path.insert(0,str(REPO/'progress/v13_r7'))
import r7_revision as r7
r7.verify_parent()
ENGINE=r7.ENGINE
from stbench.schema import Problem


def problems():
    return [Problem.load(p) for p in sorted((ROOT/'datasets').glob('*/*.json'))]


def reference(problem):
    return (ROOT/'references'/(problem.pid+'.reference.st')).read_text('utf-8')


def adapt(problem,source=None,platform='codesys',mc_seconds=None):
    p,source,mapping=r7.adapt(problem,reference(problem) if source is None else source,platform,mc_seconds)
    mapping.update(data_version=VERSION,already_adapted=True,adapted_source_sha256=digest(source.encode()))
    p.provenance['platform_adaptation']=copy.deepcopy(mapping)
    return p,source,mapping

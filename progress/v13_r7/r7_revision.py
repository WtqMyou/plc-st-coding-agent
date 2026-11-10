"""R7 extends only the formula layer; r6 functional contracts remain immutable."""
import copy
import hashlib
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parents[1]
VERSION='v1.3-judge-r7'
DATA_VERSION='v1.3-review-r6+spec-r7'


def digest(raw):return hashlib.sha256(raw).hexdigest()


def verify_parent():
    origin=json.loads((ROOT/'ORIGIN_R6.json').read_text('utf-8'))
    path=REPO/'progress/v13_r6/snapshot_manifest.json'
    assert digest(path.read_bytes())==origin['parent_manifest_sha256']
    for name,sha in json.loads(path.read_bytes())['files'].items():
        assert digest((REPO/name).read_bytes())==sha,name


verify_parent()
sys.path.insert(0,str(REPO/'progress/v13_r6'))
import r6_revision as r6
r6.verify_parent()
ENGINE=r6.ENGINE
from stbench.schema import Spec


def problems():
    overlay=json.loads((ROOT/'spec_overlay.json').read_text('utf-8'))
    result=copy.deepcopy(r6.problems())
    for problem in result:
        existing={s.sid for s in problem.specs}
        for item in overlay:
            if item['pid']!=problem.pid:continue
            assert item['sid'] not in existing
            problem.specs.append(Spec.from_dict(dict(sid=item['sid'],text=item['text'],ltl=item['formula'],
                kind='data',verified_by='test_trace_audit')))
            existing.add(item['sid'])
        problem.provenance['spec_revision']=VERSION
    return result


reference=r6.reference


def adapt(problem,*args,**kwargs):
    p,source,mapping=r6.adapt(problem,*args,**kwargs)
    mapping['spec_revision']=VERSION
    return p,source,mapping

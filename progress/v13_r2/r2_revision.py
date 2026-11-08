"""Small r2 delta over the immutable v1.3-review-r1 dataset and engine."""
from __future__ import annotations
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
PARENT = REPO/'progress/v13'
VERSION = 'v1.3-review-r2'


def digest(data): return hashlib.sha256(data).hexdigest()


def verify_parent():
    origin = json.loads((ROOT/'ORIGIN_R1.json').read_text('utf-8'))
    data = (PARENT/'snapshot_manifest.json').read_bytes()
    if digest(data) != origin['parent_manifest_sha256']:
        raise RuntimeError('Parent revision manifest changed')
    manifest = json.loads(data)
    for name, expected in {**manifest['files'], **manifest['canonical_reference_dependencies']}.items():
        if digest((REPO/name).read_bytes()) != expected:
            raise RuntimeError('Frozen r1 dependency changed: '+name)


verify_parent()
spec = importlib.util.spec_from_file_location('r1_frozen_parent', PARENT/'revision.py')
r1 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r1)
ENGINE, ENGINE_SHA256, FIVE = r1.ENGINE, r1.ENGINE_SHA256, r1.FIVE
from stbench.schema import Problem


def definitions():
    result = r1.definitions()
    for d in result:
        if d['pid'] == 'self-hard-06':
            case = next(c for c in d['test_cases'] if c['tc_id'] == 'q45')
            case['inputs']['runRequest'] = False
            case['expected'].update(currentCauseMask=0, diagnosticActive=False)
            case['note'] = ('独立非法复位：停机且压力4200，存在新复位上升沿，但pressureValid=FALSE；'
                            '仅因数据无效拒绝复位，跳闸及历史足迹1保持。本拍无运行请求，线索0、诊断FALSE。')
        elif d['pid'] == 'self-hard-07':
            next(c for c in d['test_cases'] if c['tc_id'] == 'q7')['note'] = (
                '自动模式下manualFlowSP从5变10：流量偏差从-5变0，比例项变化；'
                '积分增量为0，阀位从上一拍30%变为40%，并非阀位不变。')
        elif d['pid'] == 'self-medium-05':
            next(c for c in d['test_cases'] if c['tc_id'] == 'q18')['note'] = (
                'dt恰好10s合法：蒸汽本拍增加10×10/1000=0.1t，累计qualifiedTon=0.28t；'
                '燃料增加0.5×10/1000=0.005t，累计fuelTon=0.021t。')
        if d['source'] == 'selfmade':
            d['provenance']['review_revision'] = VERSION
    return result


def problems():
    return [Problem.load(p) for p in sorted((ROOT/'datasets').glob('*/*.json')) if not p.name.startswith('_')]


reference = r1.reference


def adapt(problem, source=None, platform='codesys', mc_seconds=None):
    if mc_seconds is None:
        mc_seconds = json.loads((ROOT/'config.offline.json').read_text('utf-8'))['mc_seconds']
    p, code, mapping = r1.adapt(problem, source, platform, mc_seconds)
    mapping['profile'] = 'portable-frame-v5+'+VERSION
    mapping['rules'].append('r2: independent invalid-sensor reset case and full-output test-contract gate')
    p.provenance['platform_adaptation'] = copy.deepcopy(mapping)
    raw = PARENT/'upstream'/p.source/(p.pid+'.json')
    original = Problem.load(raw)
    signature = lambda variables: [(x.name.lower(), x.data_type.upper(), x.direction.value) for x in variables]
    p.provenance['dataset_contract'] = dict(version=VERSION, kind='platform_adapted', platform=platform,
        original_json=raw.relative_to(REPO).as_posix(), original_sha256=digest(raw.read_bytes()),
        interface_changed=signature(original.variables)!=signature(p.variables),
        reference_source_sha256=digest(code.encode()),
        comparison_scope='Compare only within the same dataset, adaptation and judge version; not raw VARIANT conformance')
    return p, code, mapping

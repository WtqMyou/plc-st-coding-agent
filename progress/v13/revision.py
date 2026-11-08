"""v1.3 review revision, using the immutable stage-3 interpreter and judge."""
from __future__ import annotations
import copy
import hashlib
import json
import math
from pathlib import Path
import runpy
import sys

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
ENGINE = REPO / 'agent_dev_r9_stage3'
sys.path.insert(0, str(ENGINE))
from stbench.schema import Problem, Direction
from stbench.portability import adapt as base_adapt

VERSION = 'v1.3-review-r1'
FIVE = ['self-hard-05', 'self-hard-06', 'self-hard-07', 'self-medium-05', 'self-medium-06']
ENGINE_SHA256 = 'c416ac8fd0ea75dbcc40f37a88e1783d8443b6ee8cbccc347097a2c35fd4f475'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def verify_engine():
    path = REPO/'progress/evidence/r9_four_group_stage3_20261101/snapshot_manifest.json'
    pin = json.loads((REPO/'progress/evidence/r9_six_task_coverage_20261102/snapshot_manifest.json').read_text('utf-8'))
    expected = pin['prior_manifest_sha256']
    if digest(path.read_bytes()) != expected:
        raise RuntimeError('Pinned stage-3 manifest changed')
    manifest = json.loads(path.read_text('utf-8'))
    if pin['source_sha256'] != ENGINE_SHA256:
        raise RuntimeError('Unexpected evaluation engine')
    for name, expected in manifest['files'].items():
        if digest((ENGINE/name).read_bytes()) != expected:
            raise RuntimeError('Frozen engine dependency changed: '+name)


verify_engine()


def has_bit(name, bit):
    return '(' + ' OR '.join(f'{name} = {v}' for v in range(16) if v & bit) + ')'


def mask_formula():
    clauses = [f'({has_bit("latchedCauseMask", bit)} <-> (prev({has_bit("latchedCauseMask", bit)}) OR {has_bit("currentCauseMask", bit)}))'
               for bit in (1, 2, 4, 8)]
    return 'G((latchedCauseMask >= 0 AND latchedCauseMask <= 15 AND currentCauseMask >= 0 AND currentCauseMask <= 15) AND (tripLatched -> (' + ' AND '.join(clauses) + ')))'


def correct(d):
    d = copy.deepcopy(d)
    pid = d['pid']
    specs = {s['sid']: s for s in d['specs']}
    if pid == 'self-hard-07':
        lines = d['requirements'].splitlines()
        for i, line in enumerate(lines):
            if line.startswith('4.'):
                lines[i] = ('4. 模式切换当拍不执行正常 PI 积分，normalMode=FALSE。切到串级 mode=2 时，flowSP 与 valveCommand 均保持上一拍值；'
                            '切到自动/手动 mode=1/0 时，flowSP 跟随 manualFlowSP，valveCommand 保持上一拍值。连续两拍切换也必须逐拍识别。'
                            '首次执行与复位、故障拍按初始化/复位/故障规则处理，不适用上一拍输出保持。手动接管后的正常拍允许操作员给定引起阀位突变。')
            if line.startswith('扫描周期与单位约定：'):
                lines[i] = ('扫描周期与单位约定：dt 以秒给出，积分增益按秒定义，算法已显式乘 dt，不得再次折算。'
                            'KpT=1.0 (t/h)/℃，KiT=0.2 (t/h)/(℃·s)，KpF=2.0 %/(t/h)，KiF=0.5 %/((t/h)·s)。'
                            '离散采样周期会影响近似误差与闭环表现，不据此重复调整 Ki。输入契约：所有数值为有限值，manualFlowSP 在 0..50 t/h，manualValve 在 0..100%。')
            if line.startswith('3.'):
                lines[i] = line.replace('外环 KiT=0.2/s、内环 KiF=0.5/s', '外环 KiT=0.2 (t/h)/(℃·s)、内环 KiF=0.5 %/((t/h)·s)')
        d['requirements'] = '\n'.join(lines)
        guard = '(prev(TRUE) AND mode <> prev(mode) AND NOT fault AND NOT (resetBtn AND NOT prev(resetBtn)))'
        specs['S7'].update(text='非首次、无复位/故障的模式切换到自动或手动：流量跟手操，阀位保持，且本拍不正常运算；含连续切换。',
            ltl=f'G(({guard} AND mode <> 2) -> (flowSP = manualFlowSP AND valveCommand = prev(valveCommand) AND NOT normalMode))')
        specs['S8'].update(text='非首次、无复位/故障的模式切换到串级：两输出保持上一拍且不正常运算；不依赖上一拍 normalMode。',
            ltl=f'G(({guard} AND mode = 2) -> (flowSP = prev(flowSP) AND valveCommand = prev(valveCommand) AND NOT normalMode))')
    elif pid == 'self-hard-06':
        specs['S13'].update(text='跳闸期间逐位精确累积：每一历史位等于上一拍历史位或本拍线索位，且仅使用低四位。', ltl=mask_formula())
        d['requirements'] = d['requirements'].replace('跳闸整定取母管额定压力（约 4.0 MPa）之上 500 kPa，复位门槛再回退 300 kPa，', '复位门槛比跳闸门槛低 300 kPa，')
        d['requirements'] = d['requirements'].replace('（母管额定约 4.0 MPa，超压保护整定在其上 500 kPa，复位门槛回退 300 kPa）', '（不据此推定具体装置额定压力或安全阀整定值）')
    elif pid == 'self-medium-06':
        for c in d['test_cases']:
            if c['tc_id'] == 'q4':
                c['note'] = c['note'].replace('三邻域同时激活', '四条规则同时激活，其中 Z×Z 的单点输出为零')
            if c['tc_id'] == 'q13':
                c['note'] = '下限钳位：e=-10、de=0 → N×Z(-20)，bias=5，5-20=-15<0，因此 power 钳为0，correction 保持-20。'
    elif pid == 'self-hard-03':
        # All expected values follow the explicit compact-array FIFO contract.
        queues = [[], [11], [11], [11, 22], [11, 22], [11, 22, 33], [11, 22, 33], [22, 33, 44], [22, 33, 44]]
        for c, values in zip(d['test_cases'], queues, strict=True):
            c['expected']['fifo'] = values + [0] * (8 - len(values))
        d['provenance']['interface_resolution'] = '原始 input 原样留档；运行平台适配统一为 inout，与参考解和调用方可写存储一致。'
    if pid in FIVE:
        d['provenance']['human_process_review'] = dict(status='corrected_pending_rereview', reviewer='刘晏铭',
            reviewer_as_written='lym', original_conclusion='需修改', original_review_date='11.1' if pid == 'self-medium-06' else '11.2',
            source='progress/evidence/review_20261108/inputs/复核记录.md', approved=False)
    if d['source'] == 'selfmade':
        d['provenance']['review_revision'] = VERSION
    return d


def definitions():
    # One builder for the five revised tasks. Its output must match the delivered
    # JSON semantically before any downstream corrections are applied.
    module = runpy.run_path(str(ROOT / 'upstream/selfmade_new5.py'))
    generated = {p.pid: p for p in (f() for f in module['BUILDERS'])}
    out = []
    for path in sorted((ROOT / 'upstream').glob('*/*.json')):
        if path.name.startswith('_'):
            continue
        raw = json.loads(path.read_text('utf-8'))
        if raw['pid'] in generated:
            if generated[raw['pid']].to_dict() != Problem.from_dict(raw).to_dict():
                raise ValueError('Upstream generator drift: ' + raw['pid'])
        out.append(correct(raw))
    return out


def problems():
    return [Problem.load(p) for p in sorted((ROOT / 'datasets').glob('*/*.json')) if not p.name.startswith('_')]


def reference(p):
    # Keep the already validated disk references; do not restore older inline copies.
    override = ROOT / 'references' / (p.pid + '.reference.st')
    if override.is_file():
        return override.read_text('utf-8')
    return (ENGINE / 'datasets' / p.source / 'tests' / (p.pid + '.reference.st')).read_text('utf-8')


def adapt(problem, source=None, platform='codesys', mc_seconds=None):
    if mc_seconds is None:
        mc_seconds = json.loads((ROOT/'config.offline.json').read_text('utf-8'))['mc_seconds']
    if isinstance(mc_seconds, bool) or not isinstance(mc_seconds, (int, float)) or not math.isfinite(mc_seconds) or mc_seconds <= 0:
        raise ValueError('MC budget must be a finite positive number of seconds')
    p, source, mapping = base_adapt(problem, reference(problem) if source is None else source, platform)
    if p.pid == 'self-hard-03':
        next(v for v in p.variables if v.name == 'fifo').direction = Direction.INOUT
        mapping['rules'].append('v1.3 FIFO input -> inout; upstream retained, reference and caller storage unchanged')
    # base_adapt applies the historical R9 policy. Bind formulas to the new SID
    # explicitly instead of assuming that the old S8/S6 still exist.
    if p.pid == 'self-medium-05':
        legacy = next(s for s in Problem.load(ENGINE / 'datasets/selfmade/self-medium-05.json').specs if s.sid == 'S8')
        from stbench.spec_policy import apply
        probe = copy.deepcopy(p)
        probe.specs = [legacy]
        apply(probe)
        target = next(s for s in p.specs if s.sid == 'S10')
        target.text, target.ltl, target.verified_by = probe.specs[0].text, probe.specs[0].ltl, 'bounded_checker'
    if p.pid == 'self-medium-06':
        inactive = '(NOT enable OR fault OR (resetBtn AND NOT prev(resetBtn)))'
        target = next(s for s in p.specs if s.sid == 'S10')
        target.text = '功率为基础输出与修正合成后的钳位；故障、停用或复位上升沿当拍为零。'
        target.ltl = f'G(({inactive} -> power = 0.0) AND (NOT {inactive} -> ABS(power - LIMIT(0.0, bias + correction, 100.0)) <= 0.000001))'
        target.verified_by = 'bounded_checker'
    if p.pid in FIVE:
        p.provenance['human_process_review'] = copy.deepcopy(problem.provenance['human_process_review'])
        p.provenance['review'] = '已收到需修改意见；本版本已技术整改，人工复审未通过前不得标为通过。'
    p.mc_max_seconds = float(mc_seconds)
    mapping['profile'] = 'portable-frame-v5+' + VERSION
    mapping['rules'].append('Versioned v1.3 corrections; MC seconds supplied by offline run configuration')
    p.provenance['platform_adaptation'] = copy.deepcopy(mapping)
    return p, source, mapping

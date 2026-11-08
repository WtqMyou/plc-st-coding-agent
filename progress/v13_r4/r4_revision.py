"""Review-2 corrections over immutable r2 data and the r3 string judge."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
PARENT = REPO/'progress/v13_r3'
VERSION = 'v1.3-review-r4'


def digest(raw): return hashlib.sha256(raw).hexdigest()


def verify_parent():
    origin = json.loads((ROOT/'ORIGIN_R3.json').read_text('utf-8'))
    raw = (PARENT/'snapshot_manifest.json').read_bytes()
    assert digest(raw) == origin['parent_manifest_sha256'], 'r3 manifest changed'
    m = json.loads(raw)
    for name, expected in {**m['files'], **m['evidence_sha256']}.items():
        assert digest((REPO/name).read_bytes()) == expected, name
    assert digest((REPO/'progress/evidence/v13_r3_rescore_20261108b/rescore.json').read_bytes()) == m['rescore_sha256']


verify_parent()
sys.path.insert(0, str(PARENT))
import r3_revision as r3
r3.verify_parent()
r3.r2.r1.verify_engine()
ENGINE, FIVE = r3.ENGINE, r3.FIVE
CHANGED = ['self-hard-02', 'self-hard-04', 'public-medium-04']


def case(name, inputs, expected, *, mode='sequence', cycles=1, note='', const=None):
    return dict(tc_id=name, inputs=inputs, expected=expected, mode=mode, cycles=cycles,
                note=note, const_inputs=const or {}, init={}, expect_full=True)


def batch_cases():
    def b(name, start, abort, pv, limit, phase, elapsed, timeout, note):
        return case(name, dict(startBtn=start, abortBtn=abort, pv=pv),
                    dict(phase=phase, elapsed=elapsed, timeout=timeout),
                    const=dict(setpoint=100.0, maxDuration=limit), note=note)
    return [
        b('b1',True,False,20.,5,1,0,False,'启动拍不计数'),
        b('b2',True,False,60.,5,1,1,False,'按住启动不重启'),
        b('b3',False,False,100.,5,2,2,False,'达到设定值进入保温'),
        b('b4',False,False,101.,5,2,3,False,'保温计数'),
        b('b5',False,True,101.,5,9,3,False,'中止冻结计数'),
        b('b6',True,False,30.,3,1,0,False,'新的启动沿清零'),
        b('b7',False,False,40.,3,1,1,False,'升温第1拍'),
        b('b8',False,False,40.,3,1,2,False,'升温第2拍'),
        b('b9',False,False,100.,3,3,3,True,'超时和升温达标同拍，超时优先进完成态3'),
        b('b10',False,False,20.,10,3,3,True,'完成态即使时限增大仍冻结'),
        b('b11',True,True,20.,3,9,3,True,'超时后同时中止和启动，中止优先且消耗启动沿'),
        b('b12',True,False,20.,3,9,3,True,'按住启动不产生新沿，不离开中止态'),
        b('b13',False,False,20.,3,9,3,True,'松开后仍保持中止'),
        b('b14',True,False,20.,1,1,0,False,'重新按下进入新批次，不在启动拍超时'),
        b('b15',False,False,100.,1,3,1,True,'时限1拍，超时优先于达标'),
        b('b16',False,True,20.,1,9,1,True,'超时后中止保留超时标志及计数'),
        b('b17',True,False,20.,5,1,0,False,'中止后新沿可重新启动'),
        b('b18',False,True,20.,5,9,0,False,'运行中中止当拍不增加计数'),
    ]


def pump_cases():
    def p(name, demand, hours, rotated, lead, lag, *, mode='sequence:pump'):
        return case(name, dict(demand=demand, runHours=hours, rotated=rotated),
                    dict(leadPump=lead, lagPump=lag, runningCount=max(0,min(5,demand))), mode=mode)
    base = [100,200,300,400,500]
    return [
        p('p1',0,base,False,0,0,mode='single'),
        p('p2',1,base,False,1,0,mode='single'),
        p('p3',2,[500,100,300,400,200],False,2,5,mode='single'),
        p('p4',7,base,False,1,2,mode='single'),
        p('p5',-1,base,False,0,0,mode='single'),
        p('p6',2,base,True,1,2),
        p('p7',2,[100,130,300,400,500],True,1,2),
        p('p8',2,[149,100,300,400,500],True,1,2),
        p('p9',2,[150,100,300,400,500],True,1,2),
        p('p10',2,[151,100,300,400,500],True,2,1),
        p('p11',2,[151,100,300,400,500],True,2,1),
        p('p12',2,[0,100,300,400,500],False,2,1),
        p('p13',1,[0,100,300,400,500],False,2,0),
        p('p14',2,[0,100,300,400,500],False,2,1),
        p('p15',0,[0,100,300,400,500],True,0,0),
        p('p16',2,[100,100,300,400,500],True,1,2),
        p('p17',2,[100,100,100,100,100],True,1,2),
        p('p18',2,[300,200,0,400,500],True,3,2),
    ]


def heater_cases():
    rows=[]
    for suffix,end_temp in [('low',20.0),('equal',50.0),('fault',-5.0)]:
        for scan in range(1,9):
            temp=end_temp if scan==8 else 20.0
            on=scan in (1,2,3,4) or (scan==8 and suffix=='low')
            rows.append(case(f'boundary-{suffix}-{scan}',dict(TemperatureSensorInput=temp,SetTemperature=50.0),
                dict(CurrentTemperature=temp,SetTempDisplay=50.0,HeaterOutput=on,HeaterStatus=on,
                     OverheatProtection=5<=scan<=7),mode='sequence:heater-'+suffix,
                note=f'独立八拍轨迹，第{scan}拍；冷却结束输入为{suffix}'))
    # Sensor failure and equality must not pause the independent cooling counter.
    for scan,temp in enumerate([20.,20.,20.,20.,20.,-5.,50.,20.],1):
        on=scan in (1,2,3,4,8)
        rows.append(case(f'cooling-independent-{scan}',dict(TemperatureSensorInput=temp,SetTemperature=50.),
            dict(CurrentTemperature=temp,SetTempDisplay=50.,HeaterOutput=on,HeaterStatus=on,
                 OverheatProtection=5<=scan<=7),mode='sequence:heater-cooling'))
    return rows


def definitions():
    tasks=copy.deepcopy(r3.r2.definitions())
    for d in tasks:
        sid={s['sid']:s for s in d['specs']}
        if d['pid']=='self-hard-02':
            d['requirements']='''写一个功能块 FB，管理间歇反应釜批次。初始 (phase, elapsed, timeout)=(0,0,FALSE)。
1. maxDuration 为正整数，单位为扫描拍；所有实数输入为有限值，不使用系统时钟或计时器。
2. 每拍先记录 startBtn 上升沿，包括中止当拍；按 中止 > 新启动沿 > 运行计数 的优先级处理。
3. abortBtn 为 TRUE 时立即进入 phase=9，elapsed 与 timeout 保持；同拍启动沿已消耗，重新启动必须松开再按。
4. 无中止且出现新启动沿时进入 phase=1，elapsed=0、timeout=FALSE；启动拍不计数。
5. 上一拍 phase 为1或2时先将 elapsed 加1。达到本拍 maxDuration 则 timeout=TRUE、phase=3，优先于升温达标；否则 phase=1 且 pv>=setpoint 时进入 phase=2。
6. phase=3 为完成态、phase=9 为中止态，两态冻结计数及超时标志，直到新的有效启动或中止。不设无接口支持的操作员确认。'''
            d['test_cases']=batch_cases()
            sid['S1'].update(text='无中止、无新启动沿且上一拍处于运行态时，恰好计数一拍（含完成拍）。',ltl='G((prev(TRUE) AND prev(phase=1 OR phase=2) AND NOT abortBtn AND NOT (startBtn AND NOT prev(startBtn))) -> elapsed=prev(elapsed)+1)')
            sid['S2'].update(text='运行计数达到本拍正时限时进入超时完成态3。',ltl='G((prev(TRUE) AND prev(phase=1 OR phase=2) AND NOT abortBtn AND NOT (startBtn AND NOT prev(startBtn)) AND maxDuration<=prev(elapsed)+1) -> (timeout AND phase=3))')
            sid['S3'].update(text='中止优先于同拍启动，并冻结计数与超时标志。',ltl='G(abortBtn -> (phase=9 AND elapsed=prev(elapsed) AND timeout=prev(timeout)))')
            sid['S4'].update(text='完成和中止态在无新启动且无中止时保持。',ltl='G((prev(TRUE) AND prev(phase=3 OR phase=9) AND NOT abortBtn AND NOT (startBtn AND NOT prev(startBtn))) -> (phase=prev(phase) AND elapsed=prev(elapsed) AND timeout=prev(timeout)))')
            sid['S5'].update(text='仅未中止的新启动沿开始批次并清零，启动拍不计数。',ltl='G(((startBtn AND NOT prev(startBtn)) AND NOT abortBtn) -> (elapsed=0 AND NOT timeout AND phase=1))')
        elif d['pid']=='self-hard-04':
            d['requirements']='''写一个功能块 FB，管理5台并联泵的主备选择与迟滞。只验 leadPump、lagPump、runningCount，不推断其余泵的启停输出。
1. runHours[1..5] 为非负整数小时；全场按（运行小时、泵号）升序排序，同工时小泵号优先。demand 裁剪到0..5，runningCount等于裁剪后的需求。
2. 需求为0时主备都清零；重新产生正需求时按排序初选主泵。需求1时备泵为0。
3. 正需求期间保留当前主泵。rotated 按电平逐拍读取：只有请求有效且当前主泵工时比全场最短工时泵多严格超过50小时，才将最短者设为新主泵。差49或50小时均不得切换；无请求不得切换。
4. 需求至少为2时，仅在初选、从1台升至需备泵或换主时，从其余泵中选排序最小者作备泵；其余拍保持原备泵。主备必须不同，数组仅用1..5下标。
5. 独立用例各自初始化；标注相同 sequence 组名的用例在新实例中连续运行，各组互相独立并全部计分。'''
            d['case_mode']='single';d['test_cases']=pump_cases()
            sid['S1'].update(text='实际需求台数等于裁剪到0..5的需求。',ltl='G(runningCount=LIMIT(0,demand,5))')
            sid['S3'].update(text='主泵状态迟滞、严格50小时边界、备泵保持及平局顺序用独立和连续用例校验。')
        elif d['pid']=='public-medium-04':
            lines=d['requirements'].splitlines()
            lines=[('5. Each scan represents 1 second. The fifth consecutive heating-demand scan triggers protection and already turns the heater off. '
                    'Cooling starts on the next scan: two scans remain off; the third clears protection and re-evaluates the current input. '
                    'Cooling advances independently of sensor readings and faults.') if line.startswith('5.') else line for line in lines]
            d['requirements']='\n'.join(lines)
            d['requirements']+='''
本修订明确逐拍验收边界：每拍1秒。读数合法（0..100，含边界）且严格低于设定才有加热需求；等于设定或读数故障均关断并清连续加热计数。
连续需求第5拍触发过热保护，当拍已关断；从下一拍计冷却，前两拍保持关断，第3拍解除保护并按当拍读数重新决策。冷却计数独立于温度和故障；若解除当拍重新加热，该拍为下一轮第1拍。
连续低温时第1..4拍开，第5..7拍关，第8拍重新开。显示直通当前输入，HeaterStatus跟随HeaterOutput。'''
            # Existing twelve cases remain, with explicit independent trace group.
            for c in d['test_cases']:c['mode']='sequence:original'
            d['test_cases']+=heater_cases()
            sid['S3']['ltl']=sid['S3']['ltl'].replace('TemperatureSensorInput > SetTemperature','TemperatureSensorInput >= SetTemperature')
            sid['S3']['text']='读数等于或高于设定温度时关断加热。'
        if d['pid'] in CHANGED:
            d['provenance']['upstream_review_claim']=d['provenance'].get('review','')
            d['provenance']['review']='r4技术修订完成，人工工艺复审待确认；旧上游审核字样不作为本版本批准。'
            d['provenance']['human_process_review']=dict(status='r4_pending',reviewer='刘晏铭',approved=False)
            d['provenance']['review_revision']=VERSION
            d['provenance']['contract_change']='review2 verified correction; old scores are not overwritten'
    return tasks


def problems():
    from stbench.schema import Problem
    return [Problem.load(p) for p in sorted((ROOT/'datasets').glob('*/*.json')) if not p.name.startswith('_')]


def reference(p):
    path=ROOT/'references'/(p.pid+'.reference.st')
    return path.read_text('utf-8') if path.exists() else r3.reference(p)


def adapt(problem, source=None, platform='codesys', mc_seconds=None):
    p,code,mapping=r3.adapt(problem,reference(problem) if source is None else source,platform,mc_seconds)
    mapping['profile']='portable-frame-v5+'+VERSION
    mapping['rules'].append('r4: explicit batch/pump/heater contracts; isolated sequence groups')
    p.provenance['platform_adaptation']=copy.deepcopy(mapping)
    p.provenance['dataset_contract']['version']=VERSION
    p.provenance['dataset_contract']['reference_source_sha256']=digest(code.encode())
    p.provenance['dataset_contract']['working_json']='progress/v13_r4/datasets/'+p.source+'/'+p.pid+'.json'
    return p,code,mapping


def load_modelcheck():
    name='stbench.r4_modelcheck'
    if name not in sys.modules:
        spec=importlib.util.spec_from_file_location(name,ROOT/'modelcheck.py')
        module=importlib.util.module_from_spec(spec);sys.modules[name]=module;spec.loader.exec_module(module)
    return sys.modules[name]

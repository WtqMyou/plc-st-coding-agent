"""Prepare a self-contained review handout without changing frozen r6."""
import copy
import hashlib
from html import escape
import json
from pathlib import Path
import sys
import zipfile

REPO=Path(__file__).resolve().parents[2]
ROOT=REPO/'progress/review_lym_20261110'
ZIP=REPO/'progress/给lym的确认包_r6_20261110.zip'
sys.path.insert(0,str(REPO/'progress/v13_r6'))
import r6_revision as v
from conversions import runtime,checked
from stbench.st.frontend import compile_st
from stbench.st.driver import _plain


def sha(raw):return hashlib.sha256(raw).hexdigest()
def encoded(data):return (json.dumps(data,ensure_ascii=False,indent=2)+'\n').encode()


def run(source,steps,outputs):
    parsed,_=checked(compile_st(source),'codesys');assert parsed.ok
    machine=runtime('codesys').Interpreter(parsed.pou,parsed.structs);rows=[]
    for index,inputs in enumerate(steps,1):
        for key,value in inputs.items():machine.set_var(key,value)
        machine.scan()
        rows.append(dict(scan=index,inputs=inputs,outputs={k:_plain(machine.get_var(k)) for k in outputs}))
    return dict(source_sha256=sha(source.encode()),scans=rows)


def main():
    assert not ZIP.exists() and not ROOT.exists(),'Use a new handout name'
    frozen=json.loads((v.ROOT/'snapshot_manifest.json').read_text('utf-8'))
    for name,expected in frozen['files'].items():assert sha((REPO/name).read_bytes())==expected,name
    problems={p.pid:p for p in v.problems()};comparisons={}
    def incoming(pid):
        p=problems[pid]
        return (v.ROOT/'upstream/datasets'/p.source/'tests'/(pid+'.reference.st')).read_text('utf-8')
    pump=[dict(demand=2,rotated=False,runHours=[160,109,300,400,500]),
          dict(demand=3,rotated=False,runHours=[300,250,120,400,500])]
    comparisons['pump']={label:run(source,pump,['leadPump','lagPump','runningCount'])
        for label,source in [('r6',v.reference(problems['self-hard-04'])),('incoming',incoming('self-hard-04'))]}
    gate=[dict(openBtn=False,closeBtn=True,openLimit=False,closeLimit=False,obstacle=False),
          dict(openBtn=False,closeBtn=False,openLimit=False,closeLimit=False,obstacle=True),
          dict(openBtn=False,closeBtn=False,openLimit=False,closeLimit=False,obstacle=False)]
    reset=[dict(openBtn=False,closeBtn=False,openLimit=False,closeLimit=False,obstacle=True),
           dict(openBtn=True,closeBtn=True,openLimit=False,closeLimit=False,obstacle=True),
           dict(openBtn=True,closeBtn=True,openLimit=False,closeLimit=False,obstacle=False)]
    for title,steps in [('gate_obstacle',gate),('gate_reset',reset)]:
        comparisons[title]={label:run(source,steps,['motorUp','motorDown','errorFlag'])
            for label,source in [('r6',v.reference(problems['self-medium-03'])),('incoming',incoming('self-medium-03'))]}
    old_steps=[dict(VISCOSITY_OK=True,PASTE_E_STOP_NC=True,DebounceTime=500,CycleTime=100) for _ in range(5)]
    new_steps=[dict(VISCOSITY_OK=True,PASTE_E_STOP_NC=True,DebounceMs=500,CycleMs=100) for _ in range(5)]
    comparisons['jam_timing']=dict(r6=run(v.reference(problems['public-easy-04']),old_steps,['VFD_RUN','PUMP_RUNTIME_ACC']),
        incoming=run(incoming('public-easy-04'),new_steps,['VFD_RUN','PUMP_RUNTIME_ACC']),
        note='Different interfaces and runtime units: scan-count profile versus explicit milliseconds; not a head-to-head score.')
    assert comparisons['pump']['r6']['scans'][1]['outputs']['lagPump']==1
    assert comparisons['pump']['incoming']['scans'][1]['outputs']['lagPump']==3
    assert comparisons['gate_obstacle']['r6']['scans'][2]['outputs']['motorUp']
    assert not comparisons['gate_obstacle']['incoming']['scans'][2]['outputs']['motorUp']
    assert not comparisons['gate_reset']['r6']['scans'][2]['outputs']['errorFlag']
    assert comparisons['gate_reset']['incoming']['scans'][2]['outputs']['errorFlag']
    assert comparisons['jam_timing']['r6']['scans'][2]['outputs']['VFD_RUN']
    assert not comparisons['jam_timing']['incoming']['scans'][2]['outputs']['VFD_RUN']
    assert comparisons['jam_timing']['incoming']['scans'][4]['outputs']['VFD_RUN']
    record='''# lym确认记录

复核人：刘晏铭。版本：v1.3-review-r6。复核日期：________。
本表尚未填写，不代表批准。请按每一项填写结论和理由；无法判断也可明确写出。

## 1 果酱泵时间接口

现行r6保留历史TIME接口，但参考评分采用扫描计数；来件使用DebounceMs、CycleMs，运行累计单位为毫秒。连续有效输入、去抖500ms、每拍100ms时，现行第3拍启动，来件第5拍启动。两者不可混为同一口径。

选择：□ 保留扫描版作为现有实验口径，另立毫秒版；□ 后续实验统一改用毫秒版并单独重评分；□ 其他（写清）。
结论和依据：________。

## 2 多泵需求升档

第1拍demand=2、runHours=[160,109,300,400,500]、rotated=FALSE，两版均主泵2、备泵1。
第2拍demand=3、runHours=[300,250,120,400,500]、rotated=FALSE：r6保持主2备1，来件主2备3。

选择：□ 主泵未更换时备泵保持；□ 任意需求升档均重选备泵；□ 其他。
结论和依据：________。严格超过50小时及轮换请求条件是否继续适用：________。

## 3 闸门遇障与复位

下降→下一拍遇障→再下一拍障碍消失、无新按键：两版遇障当拍都停；r6随后自动上升，来件继续停机。
原题还出现“反向进入OPENING”和“障碍消失后必须重新按按钮”两种表述，不能仅凭旧参考程序判定哪个正确。

请填写每拍期望（motorUp,motorDown,errorFlag）：
下降拍：________；遇障拍：________；障碍解除且无新按钮拍：________；障碍持续下一拍：________。
FAULT时，障碍未解除就双键按住，解除后仍按住：□ 可以复位；□ 必须松开后再出现双键组合沿；□ 其他。
结论和依据：________。

## 4 三处本轮参考修复

储罐：危险液位与复位同拍仍报警，危险消失后要新的复位沿才能清除。□ 通过 □ 需修改 □ 无法判断；意见：________。
配方：非生产状态接收装载沿后，校验失败则valid=FALSE、loadedID=0。□ 通过 □ 需修改 □ 无法判断；意见：________。
灌装：fillsToday达到INT上限32767后保持、仍完成握手，复位清零后重新计数。□ 通过 □ 需修改 □ 无法判断；意见：________。

## 5 其他待复审题

请同时填写“复审记录.md”中五道工业题及r4三道修订题的结论。可以优先回复以上三处分歧和三处修复，其余注明待定。
返回本文件及已填写的复审记录即可；若改代码或题面，请另附修改文件并注明题号。自动测试记录不代替工艺判断。
'''
    rows=[]
    titles={'jam_timing':'果酱泵：500ms去抖、100ms步长','pump':'多泵：需求2→3',
            'gate_obstacle':'闸门：短障碍解除后','gate_reset':'闸门：障碍期间按住双键再解除'}
    for title,pair in comparisons.items():
        body=''
        for label in ('r6','incoming'):
            for row in pair[label]['scans']:
                body+='<tr><td>'+('现行r6' if label=='r6' else '来件')+'</td><td>'+str(row['scan'])+'</td><td>'+escape(json.dumps(row['inputs'],ensure_ascii=False))+'</td><td>'+escape(json.dumps(row['outputs'],ensure_ascii=False))+'</td></tr>'
        rows.append('<section><h2>'+titles[title]+'</h2><div class="scroll"><table><tr><th>版本</th><th>拍</th><th>输入</th><th>实际参考输出</th></tr>'+body+'</table></div></section>')
    html='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>给lym的r6确认包</title><style>body{font:16px/1.8 system-ui,"Microsoft YaHei",sans-serif;color:#243349;background:#f4f6fa;margin:0}main{max-width:1100px;margin:auto;padding:26px 20px}section{background:white;border:1px solid #dbe3ed;padding:20px;margin:18px 0;border-radius:10px}.scroll{overflow:auto}table{width:100%;border-collapse:collapse;font-size:13px}td,th{border:1px solid #dbe3ed;padding:10px;text-align:left;overflow-wrap:anywhere}th{background:#edf2f8}a{color:#175eac}pre{white-space:pre-wrap}b{color:#80540b}</style><main><h1>给lym的r6确认包</h1><p>复核人：刘晏铭 · 2026-11-10 · 当前结论均待填写</p><section><h2>先做什么</h2><p>请优先确认三个分歧：果酱泵时间接口、多泵备选、闸门遇障及复位。下方列的是两个参考程序的实测差异，供你选择规则，不代表任何一版已获工艺批准。</p><p>然后确认本轮三处修复：危险液位优先于复位、无效配方编号清零、灌装INT上限保持。其余五道工业题与r4三题继续在记录表中填写。</p><p><a href="请填写_lym确认记录.md">填写并返回这张确认表</a> · <a href="复审记录.md">其余逐题复审记录</a> · <a href="复审材料.html">35题完整题面与用例</a></p><p>无需调用模型或连接PLC；无法判断时可写明需要哪些资料。请填写实际日期，不用复制自动测试作为人工批准。</p></section>'''+''.join(rows)+'''<section><h2>证据说明</h2><p>r6参考断言1151/1151，64项回归通过，双平台各35/35。这是技术验收，不能决定工艺动作是否合理。旧Word为历史版，请以包内r6 HTML和JSON为准。</p><p>本包仅供确认，不执行代码；源码和签名置于“参考代码”“当前题目”“来件对照”及文件校验记录中。填写后把两份md记录发回即可。</p></section></main></html>'''
    entries={n:(v.ROOT/n).read_bytes() for n in ('复审材料.html','复审记录.md','采纳与核验.md')}
    entries.update({'先看这里.html':html.encode(),'请填写_lym确认记录.md':record.encode(),
        '逐拍对照.json':encoded(comparisons),'技术验收.json':(REPO/'progress/evidence/v13_r6_20261110/acceptance.json').read_bytes()})
    selected={'public-easy-04','public-medium-04','self-easy-02','self-hard-02','self-hard-04','self-hard-05','self-hard-06','self-hard-07',
              'self-medium-01','self-medium-03','self-medium-04','self-medium-05','self-medium-06'}
    for pid in sorted(selected):
        p=problems[pid]
        entries[f'当前题目/{pid}.json']=(v.ROOT/'datasets'/p.source/(pid+'.json')).read_bytes()
        entries[f'参考代码/{pid}.reference.st']=(v.ROOT/'references'/(pid+'.reference.st')).read_bytes()
    for pid in ('public-easy-04','self-hard-04','self-medium-03'):
        p=problems[pid]
        entries[f'来件对照/{pid}.json']=(v.ROOT/'upstream/datasets'/p.source/(pid+'.json')).read_bytes()
        entries[f'来件对照/{pid}.reference.st']=incoming(pid).encode()
    listing={name:dict(bytes=len(raw),sha256=sha(raw)) for name,raw in entries.items()}
    entries['文件校验.json']=encoded(dict(data_version=v.VERSION,human_review='pending',files=listing,
        parent_snapshot_sha256=sha((v.ROOT/'snapshot_manifest.json').read_bytes())))
    ROOT.mkdir(parents=True)
    for name in ('先看这里.html','请填写_lym确认记录.md','逐拍对照.json'):(ROOT/name).write_bytes(entries[name])
    with zipfile.ZipFile(ZIP,'x',compression=zipfile.ZIP_DEFLATED) as archive:
        for name,raw in sorted(entries.items()):
            info=zipfile.ZipInfo('lym确认包_r6_20261110/'+name,(2026,11,10,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
            archive.writestr(info,raw)
    with zipfile.ZipFile(ZIP) as archive:
        assert archive.testzip() is None
        assert len(archive.namelist())==len(entries)
        for name,raw in entries.items():assert archive.read('lym确认包_r6_20261110/'+name)==raw
    (ROOT/'manifest.json').write_bytes(encoded(dict(zip=ZIP.relative_to(REPO).as_posix(),zip_sha256=sha(ZIP.read_bytes()),
        builder_sha256=sha(Path(__file__).read_bytes()),files=listing,model_calls=0,human_review='pending')))
    print('PASS handout:',len(entries),'files;',ZIP.stat().st_size,'bytes; CRC and source bytes verified')


if __name__=='__main__':main()

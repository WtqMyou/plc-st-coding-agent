"""Build an audited, portable Agent engineering handoff without generation calls."""
import argparse
import ast
from collections import Counter
import csv
import difflib
import hashlib
import html
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import zipfile
sys.path.insert(0,str(Path(__file__).resolve().parent))
import f14_no80 as n

REPO=n.REPO
SOURCE=REPO/'progress/handoff_agent_20261112'
NAME='STAgent_20261112'
CACHE_SUFFIXES={'.compileinfo','.precompilecache','.opt'}
LABELS={'custom_deepseek-v4pro':'自研 DeepSeek','codex_deepseek-v4pro':'Codex DeepSeek',
        'custom_minimax-m27':'自研 MiniMax','codex_minimax-m27':'Codex MiniMax'}
PATTERN=re.compile(rb'\b(?:sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})')

def js(path,value):
    path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def copy(source,target):target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
def text(path,value):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(value,encoding='utf-8')
def csvfile(path,rows):
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('w',encoding='utf-8-sig',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)

def export_project(package,work,commit):
    archive=work/'source.tar';destination=package/'01_原工程';destination.mkdir()
    subprocess.run(['git','archive','--format=tar','--output',str(archive),commit],cwd=REPO,check=True)
    count=0
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            relative=Path(member.name)
            assert not relative.is_absolute() and '..' not in relative.parts
            assert member.isdir() or member.isfile(),'No source links or devices in handoff'
            if member.isfile():
                assert not (member.name.startswith('progress/Agent开发测试完整交接包_') or member.name.startswith('progress/handoff_parts_'))
                target=destination/relative;target.parent.mkdir(parents=True,exist_ok=True)
                with tar.extractfile(member) as src,target.open('wb') as dst:shutil.copyfileobj(src,dst)
                count+=1
    return count

def export_records(package):
    cfg,root,amend=n.locations();plan=n.load(root/'study_plan.json');audit=n.b.audit_final(cfg,root,plan)
    assert audit['passed'] and audit['jobs']==140 and audit['requests']==235
    target=package/'05_实验记录';target.mkdir()
    shutil.copytree(n.MIRROR,target/'最新正式实验')
    shutil.copytree(root/'transport_private',target/'模型调用原始传输')
    copy(cfg['budget_ledger_path'],target/'费用账本/结束账本.json')
    copy(root/'ledger_before_study.json',target/'费用账本/开始账本.json')
    copy(cfg['codesys_template'],target/'平台模板/codesys_template.project')
    latest=REPO/'11.11 复核2/STBench_F1.4-P1_公共FIFO平台复核_完整交付.zip'
    copy(latest,target/'题库原始交付'/latest.name)
    copy(latest.parent/'平台复核与变更记录.md',target/'题库原始交付/平台复核与变更记录.md')
    records=[];native_map={};native_rows=[];excluded=[]
    for job in plan['jobs']:
        record=n.load(root/'jobs'/job['condition']/(job['pid']+'.json'));records.append((job,record))
        for attempt in record['attempts']:
            build=attempt.get('judge',{}).get('platform_results',{}).get('codesys',{});folder=build.get('artifact_dir')
            if not folder:continue
            if folder not in native_map:
                tag='compile_'+str(len(native_map)+1).zfill(3)+'_'+job['pid'];native_map[folder]=tag
                for file in Path(folder).rglob('*'):
                    if not file.is_file():continue
                    if file.suffix.lower() in CACHE_SUFFIXES:
                        excluded.append(dict(kind='rebuildable_native_cache_or_personal_option',path=str(file),bytes=file.stat().st_size));continue
                    copy(file,target/'原生编译工程'/tag/file.relative_to(folder))
            native_rows.append(dict(job_id=job['job_id'],candidate_index=attempt['idx'],native_id=native_map[folder],
                package_path='05_实验记录/原生编译工程/'+native_map[folder],status=build['status'],
                source_sha256=build['source_sha256'],original_artifact_dir=folder))
    simulation=Path('E:/PLC_Dev/evidence/incoming_reviews/fifo_call_simulation_20261111_v3')
    for file in simulation.rglob('*'):
        if not file.is_file():continue
        if file.suffix.lower() in CACHE_SUFFIXES:
            excluded.append(dict(kind='rebuildable_simulation_cache',path=str(file),bytes=file.stat().st_size));continue
        copy(file,target/'FIFO双实例14步仿真'/file.relative_to(simulation))
    js(package/'07_清单指纹/原生编译索引.json',native_rows)
    js(package/'07_清单指纹/排除项说明.json',dict(never_included=['.git repository internals','API plaintext keys','DPAPI credential files','private credential binding snapshots','installed tools and licenses'],
        excluded_generated_files=excluded,all_native_project_sources_retained=True))
    return cfg,root,plan,records,len(native_map)

def export_tables(package,cfg,root,plan,records):
    destination=package/'04_数据与报告素材';summary=n.load(root/'status.json');ledger=n.load(cfg['budget_ledger_path'])
    rows=[]
    for row in summary['rows']:
        rows.append(dict(组别=row['label'],题次=35,首轮功能通过=row['first_functional'],最终功能通过=row['final_functional'],
            首轮功能通过率=round(row['first_functional']/35*100,4),最终功能通过率=round(row['final_functional']/35*100,4),
            修复新增=row['repair_gain'],首轮原生编译通过=row['first_codesys'],最终原生编译通过=row['final_codesys'],原生编译分母=34,
            功能用例通过=row['assertions_passed'],功能用例总数=946,请求数=row['requests'],
            已结算计入元=row['settled_cost_cny'],题次耗时秒=row['seconds']))
    csvfile(destination/'结果主表.csv',rows);js(destination/'结果主表.json',summary)
    detail=[]
    for job,record in records:
        a=record['attempts'][0];z=record['attempts'][record['best_attempt']]
        task_path,=list(n.b.RELEASE.glob('datasets/*/'+job['pid']+'.json'));task=n.load(task_path)
        detail.append(dict(题次=job['job_id'],题号=job['pid'],题名=task['title'],组别=LABELS[job['condition']],
            来源=task['source'],难度=task['difficulty'],候选次数=len(record['attempts']),首轮功能通过=a['functional_pass'],
            最终功能通过=z['functional_pass'],最终用例通过=z['tests_passed'],用例数=z['tests_total'],
            首轮原生编译通过=a['native_pass'],最终原生编译通过=z['native_pass'],最终形式状态=z['verification_status'],
            密钥子批次=record['credential_batch'],停止原因=record['stop_reason'],耗时秒=record['wall_seconds'],
            原始记录='05_实验记录/最新正式实验/jobs/'+job['condition']+'/'+job['pid']+'.json'))
    csvfile(destination/'逐题结果140.csv',detail)
    charges=[]
    for index,event in enumerate(ledger['events'][653:],start=653):
        request=event['request'];receipt=event['metadata']
        charges.append(dict(账本事件索引=index,请求ID=event['request_id'],题次=request['job_id'],候选序号=request['candidate_index'],
            密钥子批次=request['credential_batch'],请求模型=request['model'],回执模型=receipt['model'],协议=request['protocol'],
            输入tokens=receipt['prompt_tokens'],输出tokens=receipt['completion_tokens'],预留元=event['reserved_cny'],
            结算计入元=event['accounted_cny'],状态=event['status'],创建时间戳=event['created_at']))
    csvfile(destination/'请求费用235.csv',charges)
    formal=[]
    for row in summary['rows']:
        formal.append(dict(组别=row['label'],**{status:row['formal_statuses'].get(status,0) for status in ('bounded_pass','violated','truncated','inconclusive','not_run')}))
    csvfile(destination/'形式状态.csv',formal)
    batches=[]
    for batch in summary['credential_batches']:
        for group in batch['groups']:
            batches.append(dict(密钥子批次=batch['slot'],组别=group['label'],已完成=group['finished'],功能通过=group['functional_passed'],
                用例通过=group['cases_passed'],用例总数=group['cases_total'],该批次请求=batch['requests'],该批次计入元=batch['accounted_cny']))
    csvfile(destination/'密钥子批次.csv',batches)
    tests=[]
    for file in (package/'01_原工程').rglob('test*.py'):
        try:tree=ast.parse(file.read_text(encoding='utf-8-sig'))
        except (SyntaxError,UnicodeError):continue
        for node in ast.walk(tree):
            if isinstance(node,ast.FunctionDef) and node.name.startswith('test_'):
                tests.append(dict(测试源码=file.relative_to(package/'01_原工程').as_posix(),测试方法=node.name,行号=node.lineno))
    csvfile(destination/'回归测试索引.csv',tests)
    js(destination/'实验配置摘要.json',dict(dataset='STBench-F1.4-P1',tasks=35,cases_per_arm=946,arms=4,requests=235,
        models=cfg['models'],limits=cfg['limits'],functional_first=36,functional_final=56,custom_total=28,codex_total=28,
        new_accounted_cny=20.795950,total_accounted_cny=81.872503,native_comparable_tasks=34,
        primary_switch_cny=75,manual_pause_at_80=False,total_cap_cny=190,completed_at=n.load(root/'completion.json')['ended_at']))
    csvfile(destination/'执行时间线.csv',[dict(事件=key,时间=value) for key,value in (
        ('正式启动',n.load(root/'run_environment.json')['started_at']),('切换备用Key',n.load(root/'current_credential_batch.json')['at']),
        ('无80人工等待接续',n.load(root/'amendments/f14_remove80_20261112/state.json')['at']),('完成',n.load(root/'completion.json')['ended_at']))])
    return summary,tests

def case_materials(package,records):
    indexed={job['job_id']:record for job,record in records};metas=[]
    selections=[('native','真实编译反馈修正','custom_deepseek-v4pro/public-hard-03'),
        ('functional','功能反馈与用例提升','codex_minimax-m27/public-medium-04'),
        ('formal','形式反馈与规约修复','custom_deepseek-v4pro/public-medium-01')]
    for case,label,job_id in selections:
        record=indexed[job_id];first,last=record['attempts'];pid=record['pid'];path,=list(n.b.RELEASE.glob('datasets/*/'+pid+'.json'))
        task=n.load(path);folder=package/'03_PPT视频素材/案例'/case;folder.mkdir(parents=True)
        def descriptor(a):return dict(native=a['judge'].get('platform_results',{}).get('codesys',{}).get('status','not_run'),
            tests=a['tests_passed'],formal=a['verification_status'])
        meta=dict(case=case,label=label,job_id=job_id,pid=pid,title=task['title'],total=last['tests_total'],before=descriptor(first),after=descriptor(last))
        js(folder/'案例.json',meta);metas.append(meta)
        for tag,a in (('before',first),('after',last)):
            (folder/(tag+'.st')).write_bytes(a['code'].encode());js(folder/(tag+'.json'),a)
        text(folder/'首轮反馈.txt',first['feedback']);text(folder/'首轮题面.txt',n.load(n.b.RELEASE/'agent_inputs.json')[pid]['user'])
        js(folder/'题次原记录.json',record)
        table=difflib.HtmlDiff(wrapcolumn=100).make_table(first['code'].splitlines(),last['code'].splitlines(),fromdesc='首轮候选',todesc='唯一修复候选',context=False)
        page='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>'+html.escape(label)+'</title><style>body{font:16px/1.7 system-ui;margin:24px;color:#19334b}table.diff{font:13px/1.4 monospace;border-collapse:collapse;width:100%}.diff_header{background:#e5edf6}.diff_add{background:#d3efdb}.diff_sub{background:#ffe0dd}.diff_chg{background:#fff0b5}pre{white-space:pre-wrap;background:#eef4fa;padding:16px}</style><h1>'+html.escape(label)+'</h1><p>'+html.escape(task['title'])+' · '+html.escape(job_id)+'</p><p>真实实验记录，原生 '+meta['before']['native']+' → '+meta['after']['native']+'；功能 '+str(first['tests_passed'])+'/'+str(last['tests_total'])+' → '+str(last['tests_passed'])+'/'+str(last['tests_total'])+'；形式 '+first['verification_status']+' → '+last['verification_status']+'</p><h2>实际反馈</h2><pre>'+html.escape(first['feedback'])+'</pre><h2>代码逐行对照</h2>'+table+'</html>'
        text(folder/'代码对照.html',page)
    js(package/'03_PPT视频素材/案例索引.json',metas)
    return metas

def charts(package,summary):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.font_manager import FontProperties
    font=Path('C:/Windows/Fonts/msyh.ttc')
    if font.exists():plt.rcParams['font.family']=FontProperties(fname=str(font)).get_name()
    plt.rcParams.update({'axes.unicode_minus':False,'svg.fonttype':'none','font.size':12})
    folder=package/'03_PPT视频素材/图表';folder.mkdir(parents=True)
    labels=['自研\nDeepSeek','Codex\nDeepSeek','自研\nMiniMax','Codex\nMiniMax'];x=list(range(4));rows=summary['rows']
    for name,title,first,last,denom in (
        ('功能整题首次与最终','反馈修复提升功能整题通过数',[r['first_functional'] for r in rows],[r['final_functional'] for r in rows],35),
        ('原生编译首次与最终','真实CODESYS编译通过数',[r['first_codesys'] for r in rows],[r['final_codesys'] for r in rows],34)):
        fig,ax=plt.subplots(figsize=(10,5.4),layout='constrained');a=ax.bar([i-.2 for i in x],first,.38,color='#9fb7d0',label='首轮');z=ax.bar([i+.2 for i in x],last,.38,color='#198b80',label='最终')
        ax.bar_label(a,labels=[str(v)+'/'+str(denom) for v in first],padding=4);ax.bar_label(z,labels=[str(v)+'/'+str(denom) for v in last],padding=4)
        ax.set_xticks(x,labels);ax.set_ylim(0,denom+5);ax.set_ylabel('通过题数');ax.set_title(title);ax.legend(frameon=False);ax.spines[['top','right']].set_visible(False)
        for suffix in ('png','svg'):fig.savefig(folder/(name+'.'+suffix),dpi=200)
        plt.close(fig)
    fig,ax=plt.subplots(figsize=(8,5.2),layout='constrained');bars=ax.bar(['首轮','最多一次反馈修复后'],[36/140*100,40],color=['#9fb7d0','#198b80'],width=.5)
    ax.bar_label(bars,labels=['36/140\n25.7%','56/140\n40.0%'],padding=8);ax.set_ylim(0,55);ax.set_ylabel('功能整题通过率 / %');ax.set_title('反馈修复新增20个功能通过题次');ax.spines[['top','right']].set_visible(False)
    for suffix in ('png','svg'):fig.savefig(folder/('反馈修复总体提升.'+suffix),dpi=200)
    plt.close(fig)
    fig,ax=plt.subplots(figsize=(10,5.2),layout='constrained');values=[r['settled_cost_cny'] for r in rows];bars=ax.bar(labels,values,color=['#198b80','#587eaa','#198b80','#587eaa'])
    ax.bar_label(bars,labels=[f'{v:.2f}元' for v in values],padding=5);ax.set_ylim(0,11);ax.set_ylabel('按冻结单价及用量计入 / 元');ax.set_title('235次请求，本轮新增计入20.80元');ax.spines[['top','right']].set_visible(False)
    for suffix in ('png','svg'):fig.savefig(folder/('四组调用费用.'+suffix),dpi=200)
    plt.close(fig)

def architecture(package):
    labels=['需求与接口','模型生成通道','静态/接口检查','CODESYS编译','功能扫描测试','有界形式检查','结果归档']
    svg=['<svg xmlns="http://www.w3.org/2000/svg" width="1520" height="420" viewBox="0 0 1520 420"><defs><marker id="a" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8" fill="#43738a"/></marker></defs><rect width="1520" height="420" fill="#f5f8fc"/><g font-family="Microsoft YaHei, sans-serif"><text x="48" y="50" font-size="27" fill="#17324c">ST编程助手：生成—验证—反馈修复—归档</text>']
    for i,label in enumerate(labels):
        x=35+i*210;svg.append(f'<rect x="{x}" y="115" width="185" height="84" rx="12" fill="white" stroke="#629baf"/><text x="{x+92}" y="163" text-anchor="middle" font-size="20" fill="#17324c">{label}</text>')
        if i<6:svg.append(f'<path d="M{x+185},157 L{x+205},157" stroke="#43738a" stroke-width="2" marker-end="url(#a)"/>')
    svg.append('<path d="M1300,210 L1300,280 L340,280 L340,210" fill="none" stroke="#198b80" stroke-width="3" marker-end="url(#a)"/><text x="760" y="270" text-anchor="middle" font-size="20" fill="#12756b">实际诊断/用例/规约反馈；最多一次修复</text><text x="48" y="340" font-size="18" fill="#526b83">生成通道：自研直连 / 真实Codex CLI受控通道；统一裁判与反馈</text><text x="48" y="375" font-size="17" fill="#526b83">任务、候选、响应、费用与版本签名全程留存；FIFO原型平台限制独立标注</text></g></svg>')
    text(package/'03_PPT视频素材/Agent架构.svg',''.join(svg))
    text(package/'03_PPT视频素材/Agent架构.mmd','flowchart LR\n A[需求与接口] --> B[自研直连 / Codex CLI]\n B --> C[静态与接口检查] --> D[真实CODESYS编译] --> E[功能扫描测试] --> F[有界形式检查] --> G[证据归档]\n C & D & E & F -. 统一反馈，最多一次修复 .-> B\n')

def guides(package,summary,metas,commit):
    docs=SOURCE/'docs'
    copy(docs/'README_交接总览.md',package/'README_交接总览.md')
    for name in ('工程结构与模块说明.md','环境搭建与运行.md','测试设计与结果口径.md','数据字段与证据追溯.md','开发与版本沿革.md','预算与密钥切换说明.md','分工与交付范围.md','常见问题.md'):
        copy(docs/name,package/'02_说明'/name)
    for name in ('演示操作卡.md','可引用成果表述.md'):copy(docs/name,package/'03_PPT视频素材'/name)
    copy(docs/'报告资料索引.md',package/'04_数据与报告素材/报告资料索引.md')
    copy(docs/'可引用成果表述.md',package/'04_数据与报告素材/可引用成果表述.md')
    for file in (SOURCE/'portable').glob('*.py'):copy(file,package/'06_离线工具'/file.name)
    for filename,command in (('一键回放.cmd','offline_demo.py --case all'),('完整离线核验.cmd','verify_package.py --full')):
        (package/'06_离线工具'/filename).write_bytes(('@echo off\r\nchcp 65001 >nul\r\ncd /d "%~dp0"\r\npython -B -X utf8 '+command+'\r\npause\r\n').encode('utf-8'))
    rows=''.join('<tr><td>'+html.escape(r['label'])+'</td><td>'+str(r['first_functional'])+' → '+str(r['final_functional'])+'/35</td><td>'+str(r['first_codesys'])+' → '+str(r['final_codesys'])+'/34</td><td>'+str(r['assertions_passed'])+'/946</td></tr>' for r in summary['rows'])
    cases=''.join('<article><h3>'+html.escape(m['label'])+'</h3><p>'+html.escape(m['title'])+'</p><p>功能 '+str(m['before']['tests'])+'/'+str(m['total'])+' → '+str(m['after']['tests'])+'/'+str(m['total'])+'；形式 '+m['before']['formal']+' → '+m['after']['formal']+'</p><a href="03_PPT视频素材/案例/'+m['case']+'/代码对照.html">打开真实反馈与代码对照</a></article>' for m in metas)
    page='''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Agent开发测试交接包</title><style>body{margin:0;background:#f3f6fa;color:#19344c;font:16px/1.8 system-ui,"Microsoft YaHei",sans-serif}main{max-width:1200px;margin:auto;padding:32px 22px}h1{font-size:34px}h2{margin-top:12px}section{background:white;padding:26px;border:1px solid #dce5ef;border-radius:14px;margin:22px 0}a{color:#146f83}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:18px}article{background:#edf5f7;padding:18px;border-radius:10px}.kpi{display:flex;flex-wrap:wrap;gap:22px}.kpi div{background:#163b55;color:white;padding:20px;flex:1;min-width:160px;border-radius:10px}.kpi b{display:block;font-size:30px}table{border-collapse:collapse;width:100%}td,th{padding:12px;border-bottom:1px solid #dce5ef;text-align:left}img{width:100%;background:white}code{background:#eef3f8;padding:3px 6px}pre{overflow:auto;padding:18px;background:#edf3f8}.note{color:#526d82;font-size:14px}details{margin-top:14px}</style></head><body><main>
<h1>Agent开发与测试成果交接</h1><p>给PPT/视频同学与报告汇总/汇报同学的完整工程、证据和素材。默认离线查看，不调用生成模型。</p>
<div class="kpi"><div><b>140 / 140</b>正式题次完成</div><div><b>235</b>模型请求与结算记录</div><div><b>+20题</b>反馈修复新增功能通过</div><div><b>20.80元</b>本轮新增计入</div></div>
<section><h2>先按自己的分工领取资料</h2><div class="grid"><article><h3>PPT与视频</h3><a href="03_PPT视频素材/演示操作卡.md">演示操作卡</a><br><a href="03_PPT视频素材/图表/功能整题首次与最终.png">结果PNG图</a><br><a href="03_PPT视频素材/Agent架构.svg">架构SVG</a><p>图表、真实案例和离线回放均已准备，可按组内风格制作PPT和视频。</p></article><article><h3>报告汇总与汇报</h3><a href="04_数据与报告素材/报告资料索引.md">报告资料索引</a><br><a href="04_数据与报告素材/结果主表.csv">结果主表CSV</a><br><a href="04_数据与报告素材/可引用成果表述.md">可引用成果表述</a><p>完整140逐题表、235请求费用表、版本与证据索引可直接用于汇总。</p></article><article><h3>开发接手与答疑</h3><a href="02_说明/工程结构与模块说明.md">模块说明</a><br><a href="02_说明/环境搭建与运行.md">环境与运行</a><br><a href="01_原工程/README.md">原工程入口</a><p>保留原仓库结构、全部测试源码与开发历史，并提供跨机离线验证工具。</p></article></div></section>
<section><h2>成果判断与数据</h2><p>助手已实现真实编译、功能测试与有界形式检查的反馈闭环，整体达到本次Codex基线水平，并在MiniMax配置上略有超越。反馈修复使总体功能通过率由25.7%提升至40.0%；进一步调试与工程验证后，有望用于工业现场辅助编程。</p><table><tr><th>组别</th><th>功能首次→最终</th><th>CODESYS首次→最终</th><th>最终功能用例</th></tr>'''+rows+'''</table><p class="note">功能每组35题946用例；原生可评价34题，课程FIFO原型平台限制另列。原始成绩和检查分类均在完整数据中保留。</p><img src="03_PPT视频素材/图表/功能整题首次与最终.png" alt="四组功能通过图"><img src="03_PPT视频素材/图表/反馈修复总体提升.png" alt="反馈修复提升图"></section>
<section><h2>三个可录屏的真实案例</h2><div class="grid">'''+cases+'''</div><h3>一键回放与真实离线复验</h3><pre>python -B -X utf8 06_离线工具/offline_demo.py --case all
python -B -X utf8 06_离线工具/offline_demo.py --case functional --verify
python -B -X utf8 06_离线工具/offline_demo.py --case formal --formal-check
python -B -X utf8 06_离线工具/verify_package.py --full</pre><p>回放使用实际保存记录；--verify重新执行包内功能裁判，--formal-check补充有界检查。无需API密钥，不改写正式成绩。</p></section>
<section><h2>完整资料入口</h2><ul><li><a href="README_交接总览.md">交接总览与目录</a></li><li><a href="02_说明/分工与交付范围.md">交付范围与组员分工</a></li><li><a href="04_数据与报告素材/逐题结果140.csv">140题次CSV</a> / <a href="04_数据与报告素材/请求费用235.csv">235请求费用CSV</a> / <a href="04_数据与报告素材/形式状态.csv">形式分类CSV</a></li><li><a href="05_实验记录/最新正式实验/最终报告.md">原始正式报告</a> / <a href="05_实验记录/最新正式实验/验收包.zip">原始验收包</a></li><li><a href="07_清单指纹/原生编译索引.json">真实CODESYS工程与日志索引</a></li><li><a href="01_原工程/progress/f14_candidate/release/修订题面与用例表.html">35题题面与测试浏览</a></li><li><a href="07_清单指纹/文件清单.json">文件清单与SHA256</a></li></ul><details><summary>版本、口径和运行说明</summary><p>Git源码版本：'''+html.escape(commit)+'''。旧R8/R9与复核阶段完整保存在原工程中；当前主实验以F1.4-P1为准。原配置保留实验机路径，跨机演示请用本包相对路径工具。CODESYS安装包、许可证、API密钥和工具缓存不在包中。费用与正式记录均保留原始关联。</p></details></section></main></body></html>'''
    text(package/'00_先读我.html',page)

def scan(package):
    import f14_rotation_credentials as keys
    keys.load_credentials(n.b.config())
    secrets=[os.environ[name].encode() for name in ('DMXAPI_API_KEY',keys.SECONDARY_ENV) if os.environ.get(name)]
    count=0;expanded=0
    def check(data,label,depth=0):
        nonlocal count,expanded
        count+=1
        assert not any(value in data for value in secrets),'Real credential in '+label
        assert not PATTERN.search(data),'Credential-like token in '+label
        if depth<3 and zipfile.is_zipfile(io.BytesIO(data)):
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                for name in archive.namelist():
                    if name.endswith('/'):continue
                    value=archive.read(name);expanded+=len(value)
                    assert expanded<2*1024**3,'Nested archive scan limit'
                    check(value,label+'!'+name,depth+1)
    for path in package.rglob('*'):
        if path.is_file():check(path.read_bytes(),path.relative_to(package).as_posix())
    for name in list(os.environ):
        if 'API_KEY' in name.upper():os.environ.pop(name,None)
    return dict(passed=True,known_real_key_matches=0,generic_key_pattern_matches=0,scanned_files_and_nested_members=count,nested_bytes=expanded,
        excluded_private_credential_material=True)

def manifest(package,commit,counts):
    target=package/'07_清单指纹/文件清单.json'
    files={p.relative_to(package).as_posix():dict(bytes=p.stat().st_size,sha256=sha(p)) for p in sorted(package.rglob('*')) if p.is_file() and p!=target}
    js(target,dict(package=NAME,source_commit=commit,counts=counts,files=files,manifest_self_excluded=True))
    return files

def validation(package,work):
    relocated=work/'relocated'/NAME;shutil.copytree(package,relocated)
    env=dict(os.environ,PYTHONUTF8='1',PYTHONDONTWRITEBYTECODE='1',PYTHONNOUSERSITE='1',PYTHONPATH='')
    for name in list(env):
        if 'API_KEY' in name.upper() or name.upper() in ('GH_TOKEN','GITHUB_TOKEN'):env.pop(name,None)
    commands=[[sys.executable,'-B','-X','utf8',str(relocated/'06_离线工具/verify_package.py'),'--full'],
        [sys.executable,'-B','-X','utf8',str(relocated/'06_离线工具/offline_demo.py'),'--case','formal','--formal-check']]
    logs=[]
    for command in commands:
        result=subprocess.run(command,cwd=work,capture_output=True,text=True,encoding='utf-8',env=env,timeout=180)
        logs.append(result.stdout+'\n'+result.stderr)
        assert result.returncode==0,logs[-1][-2500:]
    return '\n\n'.join(logs)

def build(tag,commit):
    work=Path('E:/PLC_Dev/evidence/handoff_agent_20261112')/tag
    assert not work.exists(),'Never overwrite a previous handoff build'
    work.mkdir(parents=True);package=work/NAME;package.mkdir()
    commit=subprocess.check_output(['git','rev-parse',commit],cwd=REPO,text=True).strip()
    print('EXPORT source',commit,flush=True);source_count=export_project(package,work,commit)
    print('EXPORT recorded jobs/native/transport',flush=True);cfg,root,plan,records,native_count=export_records(package)
    summary,tests=export_tables(package,cfg,root,plan,records);metas=case_materials(package,records)
    guides(package,summary,metas,commit);architecture(package)
    print('RENDER reusable charts',flush=True);charts(package,summary)
    counts=dict(source_files=source_count,tasks=35,reference_cases=946,study_jobs=140,requests=235,native_builds=native_count,
        regression_test_methods_indexed=len(tests),real_case_examples=3)
    js(package/'07_清单指纹/来源与交付信息.json',dict(source_commit=commit,git_remote='https://github.com/WtqMyou/plc-st-coding-agent',
        dataset='STBench-F1.4-P1',completed_at=n.load(root/'completion.json')['ended_at'],counts=counts,
        latest_original_archive_sha256=sha(n.MIRROR/'验收包.zip'),built_at=n.stamp(),excludes='Credentials, installed software, licenses, .compileinfo/.precompilecache/.opt'))
    print('SCAN public package and nested archives',flush=True);js(package/'07_清单指纹/凭据检查.json',scan(package))
    manifest(package,commit,counts)
    print('VALIDATE relocated package with keys removed',flush=True);log=validation(package,work)
    text(package/'07_清单指纹/离线验收输出.log',log)
    text(package/'07_清单指纹/交接验收记录.md','# 交接包验收\n\n已从包内相对路径在独立位置执行：文件SHA256、140题次/235请求/费用关联、35题946条参考功能复验、三类案例功能复验、多泵案例有界形式复验。全程移除API密钥环境变量，不调用生成模型。原始工程和实验记录保持源字节。\n\n完整输出见`离线验收输出.log`，全部文件指纹见`文件清单.json`。\n')
    files=manifest(package,commit,counts)
    destination=REPO/'progress'/('Agent开发测试完整交接包_20261112'+('' if tag=='v1' else '_'+tag)+'.zip')
    assert not destination.exists(),'Never overwrite a delivered archive'
    print('ARCHIVE',len(files)+1,'files',flush=True)
    with zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for path in sorted(package.rglob('*')):
            if path.is_file():archive.write(path,NAME+'/'+path.relative_to(package).as_posix())
    with zipfile.ZipFile(destination) as archive:assert archive.testzip() is None
    receipt=dict(archive=destination.name,sha256=sha(destination),bytes=destination.stat().st_size,package_files=len(files)+1,
        source_commit=commit,source_files=source_count,counts=counts,portable_validation_passed=True,model_requests_during_build=0,
        unpacked_preview=(package/'00_先读我.html').as_posix(),manifest_sha256=sha(package/'07_清单指纹/文件清单.json'))
    js(destination.with_suffix('.manifest.json'),receipt)
    js(work/'build_receipt.json',receipt)
    print(json.dumps(receipt,ensure_ascii=False),flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--tag',default='v1');parser.add_argument('--source-commit',default='HEAD')
    args=parser.parse_args();assert re.fullmatch(r'v[0-9]+',args.tag);build(args.tag,args.source_commit)

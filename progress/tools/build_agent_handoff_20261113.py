"""Build the latest complete, audited Agent handoff. Never generates model requests."""
import argparse
import ast
from collections import Counter
from decimal import Decimal
import difflib
import hashlib
import html
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import zipfile
import f14_v14_core as s
from f14_v14_status import record_for,LABELS
import build_agent_handoff_20261112 as prior

REPO=s.REPO;SOURCE=REPO/'progress/handoff_agent_20261113';NAME='STAgent_20261113'
js,text,copy,csvfile,sha=prior.js,prior.text,prior.copy,prior.csvfile,prior.sha
CACHE={'.compileinfo','.precompilecache','.opt'}

def export_source(package,work,commit):
    tarpath=work/'source.tar';subprocess.run(['git','archive','--format=tar','--output',str(tarpath),commit],cwd=REPO,check=True)
    excluded=[];count=0
    with tarfile.open(tarpath) as archive:
        for member in archive.getmembers():
            rel=Path(member.name);assert not rel.is_absolute() and '..' not in rel.parts and (member.isfile() or member.isdir())
            if not member.isfile():continue
            if rel.suffix.lower()=='.zip' or member.name.startswith('progress/handoff_parts_'):
                excluded.append(dict(path=member.name,bytes=member.size,reason='historical/delivery archive; extracted source and records retained, avoid recursive packages'));continue
            destination=package/'01_原工程'/rel;destination.parent.mkdir(parents=True,exist_ok=True)
            with archive.extractfile(member) as source,destination.open('wb') as target:shutil.copyfileobj(source,target)
            count+=1
    return count,excluded

def export_evidence(package,cfg,root,plan):
    destination=package/'05_实验记录';latest=destination/'最新正式实验';latest.mkdir(parents=True)
    for p in s.MIRROR.iterdir():
        if p.is_file() and p.suffix!='.zip':copy(p,latest/p.name)
        elif p.is_dir() and p.name not in ('jobs','native_evidence','imported_v13'):shutil.copytree(p,latest/p.name)
    for name in ('study_plan.json','completion.json','full_audit.json','run_environment.json'):
        copy(s.IMPORTED_ROOT/name,latest/'导入20题来源'/name)
    copy(cfg['budget_ledger_path'],destination/'费用账本/结束账本.json')
    copy(root/'ledger_before_study.json',destination/'费用账本/开始账本.json')
    copy(s.IMPORTED_ROOT/'ledger_before_study.json',destination/'费用账本/V13开始账本.json')
    copy(cfg['codesys_template'],destination/'平台模板/codesys_template.project')
    teacher=REPO/'11.11 复核2/STBench_F1.4-P1_公共FIFO平台复核_完整交付.zip'
    if teacher.exists():
        copy(teacher,destination/'题库原始交付'/teacher.name)
        review=teacher.parent/'平台复核与变更记录.md'
        if review.exists():copy(review,destination/'题库原始交付'/review.name)
    origins=[];records=[];native_map={};native_rows=[];excluded=[]
    waitmeta=s.load(root/'restart_v4_ready.json');wait900=set(s.load(root/waitmeta['directory']/'recovery.json')['wait900_jobs'])
    for job in plan['jobs']+plan['imported_jobs']:
        record=record_for(root,job);assert record['job_done'];records.append((job,record))
        source_root=s.IMPORTED_ROOT if job.get('imported') else root;folder=source_root/'jobs'/job['condition']
        for p in folder.glob(job['pid']+'.*'):
            if p.is_file() and p.suffix in ('.json','.st'):copy(p,latest/'jobs'/job['condition']/p.name)
        relative='05_实验记录/最新正式实验/jobs/'+job['job_id']+'.json'
        origins.append(dict(job_id=job['job_id'],pid=job['pid'],condition=job['condition'],imported_v13=bool(job.get('imported')),
            phase='f14_v13_self_20261113' if job.get('imported') else s.KIND,record=relative,
            record_sha256=sha(source_root/'jobs'/job['condition']/(job['pid']+'.json')),network_wait_seconds=900 if job['job_id'] in wait900 else 420))
        for a in record['attempts']:
            private=source_root/'transport_private'/job['condition']/job['pid']/str(a['idx'])
            for p in private.rglob('*'):
                if p.is_file():
                    assert p.name in ('diagnostic.json','worker_result.json','http_body.bin','worker.stderr.log'),p
                    copy(p,destination/'模型调用原始传输'/job['condition']/job['pid']/str(a['idx'])/p.name)
            native=a.get('judge',{}).get('platform_results',{}).get('codesys',{});directory=native.get('artifact_dir')
            if not directory:continue
            if directory not in native_map:
                tag=f'compile_{len(native_map)+1:03}_{job["pid"]}';native_map[directory]=tag
                for p in Path(directory).rglob('*'):
                    if not p.is_file():continue
                    if p.suffix.lower() in CACHE:excluded.append(dict(path=str(p),bytes=p.stat().st_size,reason='rebuildable compiler cache or personal UI setting'));continue
                    copy(p,destination/'原生编译工程'/tag/p.relative_to(directory))
            native_rows.append(dict(job_id=job['job_id'],candidate_index=a['idx'],native_id=native_map[directory],
                package_path='05_实验记录/原生编译工程/'+native_map[directory],status=native['status'],source_sha256=native['source_sha256'],original_artifact_dir=directory))
    js(package/'07_清单指纹/题次来源索引.json',origins);js(package/'07_清单指纹/原生编译索引.json',native_rows)
    return records,origins,len(native_map),excluded

def tables(package,cfg,root,records,origins):
    destination=package/'04_数据与报告素材';status=s.load(root/'status.json');ledger=s.load(cfg['budget_ledger_path'])
    event_map={(e['phase'],e.get('request',{}).get('job_id'),e.get('request',{}).get('candidate_index')):(i,e) for i,e in enumerate(ledger['events'])}
    origin_map={o['job_id']:o for o in origins};charges=[];detail=[];failures=[];first_native=Counter();complete=Counter()
    for job,record in records:
        first=record['attempts'][0];best=record['attempts'][record['best_attempt']];task=s.tasks()[job['pid']];origin=origin_map[job['job_id']]
        first_native[job['condition']]+=bool(first['native_pass']);complete[job['condition']]+=bool(best['complete_code'])
        row=dict(题次=job['job_id'],题号=job['pid'],题名=task['title'],组别=LABELS[job['condition']],来源='公共' if job['pid'].startswith('public-') else '自建',难度=task['difficulty'],
            候选次数=len(record['attempts']),首轮功能通过=first['functional_pass'],最终功能通过=best['functional_pass'],最终用例通过=best['tests_passed'],用例数=best['tests_total'],
            原生编译通过=best['native_pass'],原生可评价=job['pid']!='public-hard-04',最终形式状态=best['verification_status'],
            网络等待上限秒=origin['network_wait_seconds'],导入V13已完成记录=origin['imported_v13'],停止原因=record['stop_reason'],活动耗时秒=record['wall_seconds'],原始记录=origin['record'])
        detail.append(row)
        if not best['functional_pass']:failures.append(row)
        for a in record['attempts']:
            index,e=event_map[(origin['phase'],job['job_id'],a['idx'])];q=e['request'];receipt=e.get('metadata',{})
            charges.append(dict(账本索引=index,请求ID=e['request_id'],实验阶段=e['phase'],题次=job['job_id'],候选序号=a['idx']+1,候选原索引=a['idx'],
                组别=LABELS[job['condition']],协议=q['protocol'],请求模型=q['model'],回执模型=receipt.get('model',''),
                输入tokens=receipt.get('prompt_tokens',''),输出tokens=receipt.get('completion_tokens',''),输出上限=q['max_output_tokens'],
                网络等待上限秒=q['timeout_seconds'],预留元=e['reserved_cny'],状态=e['status'],结算计入元=e.get('accounted_cny',''),
                保留未知费用元=e['reserved_cny'] if e['status']=='reserved' else 0,密钥子批次=q['credential_batch'],
                原始响应=f'05_实验记录/最新正式实验/jobs/{job["condition"]}/{job["pid"]}.response_{a["idx"]+1:02}.json' if e['status']=='settled' else '',
                原始传输=f'05_实验记录/模型调用原始传输/{job["condition"]}/{job["pid"]}/{a["idx"]}'))
    assert len(detail)==140 and len(charges)==306 and len({r['请求ID'] for r in charges})==306
    csvfile(destination/'逐题结果140.csv',detail);csvfile(destination/'请求费用306.csv',charges);csvfile(destination/'未通过题次.csv',failures)
    main=[];formal=[]
    for r in status['rows']:
        main.append(dict(组别=r['label'],功能首轮通过=r['first_functional'],功能最终通过=r['final_functional'],功能题数=35,最终通过率百分比=round(r['final_functional']/35*100,4),
            公共题通过=r['groups']['public']['functional'],公共题分母=20,自建题通过=r['groups']['self_built']['functional'],自建题分母=15,
            首轮原生编译通过=first_native[r['condition']],最终原生编译通过=r['native_passed'],原生分母=34,最终完整代码=complete[r['condition']],
            用例通过=r['assertions_passed'],用例分母=946,修复新增=r['repair_gain'],请求数=r['requests']))
        formal.append(dict(组别=r['label'],有界通过=r['formal_statuses'].get('bounded_pass',0),报告违反=r['formal_statuses'].get('violated',0),搜索截断=r['formal_statuses'].get('truncated',0),未决=r['formal_statuses'].get('inconclusive',0),未执行=r['formal_not_executed']))
    csvfile(destination/'结果主表.csv',main);js(destination/'结果主表.json',status);csvfile(destination/'形式状态.csv',formal)
    csvfile(destination/'等待策略分项.csv',status['wait_policy_cohorts'])
    csvfile(destination/'题库35题索引.csv',[dict(题号=pid,题名=p['title'],来源=p['source'],难度=p['difficulty'],用例数=len(p['test_cases']),
        题目数据='01_原工程/progress/f14_agent_v14/release/'+next(s.RELEASE.glob('datasets/*/'+pid+'.json')).relative_to(s.RELEASE).as_posix()) for pid,p in s.tasks().items()])
    tests=[]
    for p in (package/'01_原工程').rglob('test*.py'):
        try:tree=ast.parse(p.read_text(encoding='utf-8-sig'))
        except (SyntaxError,UnicodeError):continue
        for node in ast.walk(tree):
            if isinstance(node,ast.FunctionDef) and node.name.startswith('test_'):tests.append(dict(测试源码=p.relative_to(package/'01_原工程').as_posix(),方法=node.name,行号=node.lineno))
    csvfile(destination/'回归测试源码索引.csv',tests)
    js(destination/'实验配置摘要.json',dict(dataset='STBench-F1.4-P1',tasks=35,cases_per_arm=946,arms=4,requests=306,
        limits=cfg['limits'],models=cfg['models'],operational_minimax_wait_seconds=900,task_seconds=2400,
        first_functional=67,final_functional=91,custom_final=46,codex_final=45,custom_repair_gain=14,codex_repair_gain=10,
        new120_accounted_cny=status['new_accounted_cny'],project_accounted_cny=ledger['spent_cny'],project_cap_cny=480,
        unknown_requests_retained=8,unknown_reserved_cny=2.643027,completed_at=s.load(root/'completion.json')['at']))
    return status,len(tests)

def case_materials(package,records):
    indexed={j['job_id']:r for j,r in records};specs=[
        ('native','真实编译反馈修复','custom_deepseek-v4pro/public-hard-03',0,1,'latest','本轮140题次'),
        ('functional','温控功能反馈修复','custom_deepseek-v4pro/public-medium-04',0,1,'latest','本轮140题次（V13导入20题之一）'),
        ('formal','形式反馈减少违反','custom_deepseek-v4pro/public-medium-01',0,1,'latest','本轮140题次；两条违反减少至一条，属于部分修复'),
        ('formal_legacy','历史形式反馈修复成功','custom_deepseek-v4pro/public-medium-01',0,1,'legacy','历史正式实验2026-11-12；不并入本轮成绩')]
    metas=[]
    for key,label,job_id,before,after,release,label_source in specs:
        record=indexed[job_id] if release=='latest' else s.load(Path('E:/PLC_Dev/evidence/real_experiments/f14_p1_20261111b/jobs')/(job_id+'.json'))
        a=record['attempts'][before];z=record['attempts'][after];pid=record['pid'];folder=package/'03_PPT视频素材/案例'/key
        def desc(x):return dict(native=x['judge'].get('platform_results',{}).get('codesys',{}).get('status','not_run'),tests=x['tests_passed'],formal=x['verification_status'],violations=len(x['judge'].get('model_check',{}).get('violations',[])))
        meta=dict(case=key,label=label,job_id=job_id,pid=pid,title=s.tasks()[pid]['title'],total=z['tests_total'],before=desc(a),after=desc(z),
            before_candidate=before+1,after_candidate=after+1,release_key=release,source_label=label_source)
        js(folder/'案例.json',meta);js(folder/'题次原记录.json',record);metas.append(meta)
        for name,attempt in [('before',a),('after',z)]:
            folder.mkdir(parents=True,exist_ok=True);(folder/(name+'.st')).write_bytes(attempt['code'].encode());js(folder/(name+'.json'),attempt)
        text(folder/'首轮反馈.txt',a['feedback']);text(folder/'首轮题面.txt',s.load(s.RELEASE/'agent_inputs.json')[pid]['user'])
        table=difflib.HtmlDiff(wrapcolumn=100).make_table(a['code'].splitlines(),z['code'].splitlines(),fromdesc='修复前候选',todesc='模型修复后候选',context=False)
        page=f'<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>{html.escape(label)}</title><style>body{{font:16px/1.8 system-ui;margin:28px;color:#17324c}}pre{{white-space:pre-wrap;background:#eef4fa;padding:20px}}table.diff{{font:12px/1.5 monospace;width:100%}}.diff_add{{background:#d9f3e6}}.diff_sub{{background:#ffe0dd}}.diff_chg{{background:#fff2bd}}</style><h1>{html.escape(label)}</h1><p>{html.escape(label_source)}</p><p>{html.escape(job_id)} · 候选{before+1}→{after+1}</p><p>原生：{meta["before"]["native"]} → {meta["after"]["native"]}；功能：{a["tests_passed"]}/{z["tests_total"]} → {z["tests_passed"]}/{z["tests_total"]}；形式：{a["verification_status"]} → {z["verification_status"]}；报告违反：{meta["before"]["violations"]} → {meta["after"]["violations"]}</p><h2>实际反馈</h2><pre>{html.escape(a["feedback"])}</pre><h2>代码对照</h2>{table}</html>'
        text(folder/'代码对照.html',page)
    js(package/'03_PPT视频素材/案例索引.json',metas)
    return metas

def charts(package,status):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.font_manager import FontProperties
    font=Path('C:/Windows/Fonts/msyh.ttc')
    if font.exists():plt.rcParams['font.family']=FontProperties(fname=str(font)).get_name()
    plt.rcParams.update({'axes.unicode_minus':False,'svg.fonttype':'none','font.size':12})
    folder=package/'03_PPT视频素材/图表';folder.mkdir(parents=True)
    rows=status['rows'];labels=['自研\nDeepSeek','Codex\nDeepSeek','自研\nMiniMax','Codex\nMiniMax'];x=list(range(4))
    def save(fig,name):
        for extension in ('png','svg'):fig.savefig(folder/(name+'.'+extension),dpi=200)
        plt.close(fig)
    fig,ax=plt.subplots(figsize=(10.5,5.5),layout='constrained')
    for offset,field,color,label in [(-.2,'first_functional','#a6b9cd','首候选'),(.2,'final_functional','#16857b','反馈修复后')]:
        bars=ax.bar([v+offset for v in x],[r[field] for r in rows],.38,color=color,label=label)
        ax.bar_label(bars,labels=[f'{r[field]}/35' for r in rows],padding=5)
    ax.set_xticks(x,labels);ax.set_ylim(0,40);ax.set_ylabel('功能整题通过数');ax.set_title('最新35题四组对照：首候选与反馈修复后');ax.legend(frameon=False);ax.spines[['top','right']].set_visible(False);save(fig,'四组功能首轮与最终')
    fig,ax=plt.subplots(figsize=(10.5,5.5),layout='constrained')
    for offset,group,n,color,label in [(-.2,'public',20,'#4e79a7','公共题（20题）'),(.2,'self_built',15,'#16857b','自建题（15题）')]:
        values=[r['groups'][group]['functional'] for r in rows];bars=ax.bar([v+offset for v in x],[100*v/n for v in values],.38,color=color,label=label)
        ax.bar_label(bars,labels=[f'{v}/{n}\n{v/n:.0%}' for v in values],padding=5)
    ax.set_xticks(x,labels);ax.set_ylim(0,118);ax.set_ylabel('功能整题通过率 / %');ax.set_title('公共题与自建题分项');ax.legend(frameon=False,loc='upper right');ax.spines[['top','right']].set_visible(False);save(fig,'公共题与自建题')
    fig,ax=plt.subplots(figsize=(8.5,5.5),layout='constrained');bars=ax.bar(['自研框架','Codex基线'],[46,45],width=.48,color=['#16857b','#4e79a7'])
    ax.bar_label(bars,labels=['46/70 · 65.7%','45/70 · 64.3%'],padding=6);ax.set_ylim(0,70);ax.set_ylabel('两模型合计功能通过数');ax.set_title('本轮自研合计略高1题');ax.spines[['top','right']].set_visible(False);save(fig,'两框架合计')
    fig,ax=plt.subplots(figsize=(9,5.2),layout='constrained');bars=ax.bar(['首候选','反馈修复后'],[67,91],width=.48,color=['#a6b9cd','#16857b'])
    ax.bar_label(bars,labels=['67/140 · 47.9%','91/140 · 65.0%'],padding=7);ax.set_ylim(0,140);ax.set_ylabel('功能整题通过数');ax.set_title('反馈修复新增24题：自研14题、Codex10题');ax.spines[['top','right']].set_visible(False);save(fig,'反馈修复总体增益')
    fig,ax=plt.subplots(figsize=(11,5.5),layout='constrained');bottom=[0]*4
    for key,label,color in [('bounded_pass','有界通过','#16857b'),('violated','报告违反','#d56a61'),('truncated','搜索截断','#e4ad54'),('inconclusive','未决','#8d94b9'),('not_executed','未执行','#d4dbe4')]:
        values=[r['formal_not_executed'] if key=='not_executed' else r['formal_statuses'].get(key,0) for r in rows]
        bars=ax.bar(x,values,bottom=bottom,label=label,color=color)
        for i,value in enumerate(values):
            if value:ax.text(i,bottom[i]+value/2,str(value),ha='center',va='center',fontsize=11)
        bottom=[a+b for a,b in zip(bottom,values)]
    ax.set_xticks(x,labels);ax.set_ylim(0,39);ax.set_ylabel('最终候选题次');ax.set_title('形式检查单独统计（每组35题）');ax.legend(ncol=5,loc='upper center',frameon=False,fontsize=10);ax.spines[['top','right']].set_visible(False);save(fig,'形式检查状态')
    svg=['<svg xmlns="http://www.w3.org/2000/svg" width="1500" height="380"><defs><marker id="a" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8" fill="#54728c"/></marker></defs><rect width="1500" height="380" fill="#f3f7fb"/><g font-family="Microsoft YaHei,sans-serif" fill="#18354e"><text x="35" y="48" font-size="28">ST助手：生成—编译—功能—形式—反馈修复</text>']
    for i,label in enumerate(['公开需求与接口','模型/CLI通道','静态与接口检查','CODESYS编译','功能扫描测试','有界形式检查','证据与费用归档']):
        x0=25+i*210;svg.append(f'<rect x="{x0}" y="105" width="190" height="85" rx="12" fill="white" stroke="#83a0b7"/><text x="{x0+95}" y="155" text-anchor="middle" font-size="19">{label}</text>')
        if i<6:svg.append(f'<path d="M{x0+190},147 L{x0+207},147" stroke="#54728c" stroke-width="2" marker-end="url(#a)"/>')
    svg.append('<path d="M1280,200 L1280,273 L330,273 L330,200" fill="none" stroke="#16857b" stroke-width="3" marker-end="url(#a)"/><text x="755" y="260" text-anchor="middle" font-size="20" fill="#16857b">实际错误与轨迹 → 模型精确补丁 → 最多4候选</text><text x="35" y="337" font-size="18">同一模型、题库与裁判；独立保留编译、功能、形式三类结果；密钥、预算和证据归档受保护。</text></g></svg>')
    text(package/'03_PPT视频素材/Agent架构.svg',''.join(svg))

def md_html(markdown):
    def inline(value):
        value=html.escape(value)
        value=re.sub(r'\[([^\]]+)\]\(([^)]+)\)',r'<a href="\2">\1</a>',value)
        value=re.sub(r'\*\*([^*]+)\*\*',r'<strong>\1</strong>',value)
        return re.sub(r'`([^`]+)`',r'<code>\1</code>',value)
    out=[];table=False
    for line in markdown.splitlines():
        if line.startswith('|'):
            if not table:out.append('<table>');table=True
            cells=[c.strip() for c in line.strip('|').split('|')]
            if all(re.fullmatch(r':?-+:?',c) for c in cells):continue
            out.append('<tr>'+''.join('<td>'+inline(c)+'</td>' for c in cells)+'</tr>');continue
        if table:out.append('</table>');table=False
        if line.startswith('#'):
            n=len(line)-len(line.lstrip('#'));out.append(f'<h{n}>'+inline(line[n:].strip())+f'</h{n}>')
        elif line.startswith('- '):out.append('<p>• '+inline(line[2:])+'</p>')
        elif line.strip():out.append('<p>'+inline(line)+'</p>')
    if table:out.append('</table>')
    return '<!doctype html><html lang="zh-CN"><meta charset="utf-8"><style>body{max-width:1100px;margin:35px auto;padding:20px;font:16px/1.8 system-ui;color:#19374c}table{border-collapse:collapse;width:100%}td{padding:9px;border:1px solid #d9e3eb}code{background:#eef4f8;padding:3px}a{color:#087c79}</style>'+''.join(out)+'</html>'

def guides(package,status,metas,commit,counts):
    def doc(folder,name,body):
        text(package/folder/(name+'.md'),body);text(package/folder/(name+'.html'),md_html(body))
    docs={
    '工程结构与模块说明':'''# 工程结构与模块说明
最新编程助手入口为01_原工程/progress/tools/f14_v14_core.py；最新冻结题库和裁判在progress/f14_agent_v14/。该目录复用v13_命名的纯策略模块，命名保留以便逐字节追溯。
- 需求与提示：core.messages、agent_inputs.json、v13_contracts.py、v13_time_bounds.py；题面保持原文，只提供公开接口和时间边界演算。
- 模型和Codex通道：progress/tools/full_r8b_transport.py、progress/f14_candidate/codex_transport.py；基线通过真实Codex CLI及隔离网关转发同一个模型，关闭额外工具和仓库读取。
- 输出提取与格式：v13_extraction.py、v13_formatting.py；保留模型原文，仅有记录明确的分号格式处理。
- 修复：v13_repairs.py、v13_repair_selection.py；模型生成唯一锚点JSON补丁，宿主只应用精确编辑，保留原始补丁和展开后的完整程序。
- 编译与测试：judge_worker.py、release/stbench/st/及agent_dev_r9_stage3/stbench/platforms.py；真实CODESYS编译后进行扫描测试，功能全通过后进入有界形式检查。
- 反馈：完整公开输入前缀、候选实际输出和TON状态；明确单字段失败与输出组合失败；不向模型提供参考解或隐藏断言期望。
- 预算与调度：f14_v14_budget.py、f14_v14_study.py，后续运行恢复入口resume_latest_140*.py。原生编译独占、模型请求分路、历史费用与未知预留保留。
- 运行变更：resume_latest_140_v4.py延长MiniMax网络等待到900秒，单题2400秒不变；已有420秒结果保留，两个MiniMax框架后段均为相同26题。
原工程保留agent_dev、agent_dev_r9、agent_dev_r9_stage3及progress的版本化源码、测试和历史证据。根目录的最新结果与旧实验分开，不改写历史成绩。
''',
    '环境搭建与运行':'''# 环境搭建与运行
## 最快查看
双击根目录00_先读我.html。所有图表、数据表、指南和案例在包内，不需要联网或API密钥。
## 离线回放与校验
推荐Python 3.12。离线工具只依赖Python标准库；建议解压到D:/STAgent等短路径。
- python -B -X utf8 06_离线工具/verify_package.py
- python -B -X utf8 06_离线工具/verify_package.py --full
- python -B -X utf8 06_离线工具/offline_demo.py --case all --verify
- python -B -X utf8 06_离线工具/offline_demo.py --case formal_legacy --formal-check
也可以双击06_离线工具中的一键回放.cmd和一键核验.cmd。--verify重新执行包内功能裁判；CODESYS结果按原始日志、nonce和代码指纹核验。形式检查可选，单次最多30秒，新的计时截断结果作为离线复验输出，不覆盖正式记录。
## 继续开发
先阅读工程结构、冻结配置和运行恢复说明。原配置中的E:/PLC_Dev是实验机历史路径；迁移时为新运行准备独立配置和证据目录，并安装CODESYS 3.5 SP22 Patch 4、Python、Codex CLI及工程依赖。重新绘图需要matplotlib；本机运行辅助还用psutil和Windows DPAPI。
本包不含安装包、许可证、API明文密钥和DPAPI密文。付费入口需要单独配置可用密钥、预算和环境签名，提交推送后再启动。不要覆盖本轮冻结配置或原始答卷；新开发结果使用新批次归档。
''',
    '测试设计与结果口径':'''# 测试设计与结果口径
STBench-F1.4-P1共35题：公共20题470用例，自建15题476用例。两模型×两框架共140题次，每组35题946用例。每题最多4候选，包含首候选和至多3次反馈修复。首次完整代码、原生编译、功能整题与用例、形式结果分别统计。
V13自研DeepSeek公共20题独立验证为18/20、430/470；主实验绑定这20份原始记录，只新增其余120题次。两部分使用相同V13提示、反馈和裁判策略，导入记录保持原始文件与SHA256。
DeepSeek单次网络等待420秒。MiniMax前9题/组为420秒，后26题/组为900秒；两个框架后26题集合相同。输出24576、单题2400秒、最多4候选保持。请求等待时限及账本事件可逐条核对，分项表在等待策略分项.csv。
原VARIANT FIFO保留功能测试；当前CODESYS原始接口不支持，所以原生分母为34，功能分母仍为35。不能以本地解释器通过代替原生编译通过；模拟量批处理本地可执行但原生失败的候选仍按正式编译门槛记录。
形式检查在功能成功后执行。最终候选有界通过29、报告违反16、搜索截断30、未决16、未执行49。bounded_pass指本轮声明范围内完成有界检查；功能通过与形式结果分别保留。
未得到完整代码、超时和调用故障均保留题次分母；8条异常费用预留继续保留，没有重复发送对应的旧请求。余额不足拒绝后，经用户确认充值从下一候选接续，拒绝请求仍计入每题4次上限。
''',
    '数据字段与证据追溯':'''# 数据字段与证据追溯
以04_数据与报告素材/逐题结果140.csv定位题次，再打开原始记录列指向的JSON。attempts保存每次候选，best_attempt为0起始的最终保留候选索引。
- *.request_NN.json：实际上游消息和冻结参数；timeout_seconds记录实际网络等待。
- *.response_NN.json：原始模型响应；缺失响应的异常请求在原始传输目录保留诊断与部分/空响应体。
- *.raw_candidate_NN.st与*.candidate_NN.st：模型候选展开文本和格式处理后文本。
- *.model_patch_NN.json与*.patch_base_NN.st：模型精确补丁和被修改候选，可按包内工具重放验证。
- judge：编译、功能逐例、形式结果及反馈；platform_results.codesys指向实验机历史路径，包内相对路径请查07_清单指纹/原生编译索引.json。
- 请求费用306.csv：按原始账本事件索引、请求ID、阶段、候选索引关联。候选序号从1起，候选原索引从0起。20份导入记录使用V13阶段，剩余120题次使用V14阶段，避免同题号跨实验误关联。
源码按明确Git提交导出，题次和候选文件按原始字节复制。题次来源索引同时保存导入标记、源记录哈希与等待批次。冻结文件、原生nonce、代码、费用和补丁重放均由离线校验器核对。
回归测试源码索引列出随包源码中的测试方法，属于定位索引；实际已执行检查见实验validation.json、free_tests.log及各次恢复的tests.log。
''',
    '预算与运行恢复说明':'''# 预算与运行恢复说明
项目累计授权上限480元，最终计入211.178859元；本次补齐120题次新增计入28.551264元。20份导入答卷在先前账本中已经计费，不重复相加到项目余额。
最新140题次共306次请求，43次属于导入20题，263次属于本次补齐120题。账本中8条异常预留共2.643027元保持：7次超时、1次余额不足拒绝。费用字段为冻结单价与用量的项目计入金额，包含保留预留。
480元是项目运行保护上限，不等于DMXAPI账号的实际可用余额。余额不足会返回403，用户充值后才恢复。旧Key到75元前切换备用Key、取消80元人工暂停等历史操作保留在原工程和账本中，当前批次使用备用Key。
恢复先检查运行进程、账本签名和HTTP原始记录，保留未知预留和所有已完成答卷。中断但未发送下一请求的题次从下一候选接续；已发送请求按事件ID去重。每次恢复都有快照、检查、代码签名及用户指令记录。
为解决MiniMax长请求反复触发420秒硬超时，后段26题/组使用900秒网络等待；单题2400秒不足容纳下一请求和评测时保存当前结果，不再发起下一候选。输出与候选上限、模型参数及裁判不变。
''',
    '分工与交付范围':'''# 分工与交付范围
Agent侧交付：原工程、版本化题库和裁判、完整实验记录、费用与校验材料、离线回放、真实修复案例、可复用图表及数据。
- PPT/视频同学：使用03_PPT视频素材的PNG/SVG、架构图、操作卡和案例HTML；可录制离线回放，不需要再次付费调用模型。
- 报告汇总/汇报同学：使用04_数据与报告素材主表、140逐题表、306请求费用表、等待策略分项和可引用表述；按证据索引定位原始答卷。
- 开发接手：使用01_原工程和本目录的结构、环境、测试口径、费用恢复及遗留任务说明。
本包提供汇报素材与工程交接，PPT、视频及最终项目报告由原分工的两位同学完成。
''',
    '开发版本与剩余工作':'''# 开发版本与剩余工作
旧R8/R9、复核r1–r8、F1.4-P1及20261112正式实验和旧交接包均保留在源仓库。旧交接包对应235请求、15/17/13/11成绩，是历史版本。
随后V10完成新的140题次；V11自研DeepSeek公共题达到16/20；V12–V13改进方向互锁、输出保持、计时器反馈、VARIANT工具接口和明确失败字段，V13独立公共20题达到18/20。
最新主实验以V13策略绑定20份独立答卷，再补齐120题，最终33/34/13/11；原生、功能、形式、费用与网络等待批次均分别记录。
当前Agent实现、测试闭环与140题次覆盖已经完成。接下来以交接收尾为主：更新报告素材、展示真实反馈修复、按清单回应技术答疑。
后续若继续提高准确率，优先看自研DeepSeek剩余两题：public-medium-02模拟量批处理的原生编译问题；public-medium-06板坯报警的输出完整性。Codex DeepSeek剩余public-hard-06为功能用例31/49。MiniMax另有语义错误、生成完整性及部分本地建模未决，见未通过题次表。新修改进入独立版本，不替换本轮成绩。
''',
    '常见问题':'''# 常见问题
## 本轮成果怎么概括？
自研DeepSeek33/35（94.3%），公共18/20、自建15/15。两模型合计自研46/70、Codex45/70，自研多通过1题；自研修复新增14题、Codex新增10题，流程已展现工程可行性。
## 140题次是否全部通过？
140题次全部覆盖；功能最终通过91题。两模型都保留失败分母。DeepSeek两组33、34题，MiniMax两组13、11题，模型差异在本题库上较明显。
## 为什么原生编译分母34，功能分母35？
课程FIFO原VARIANT接口在当前原生平台不支持，功能测试仍保留原接口与实际数组绑定，单独记录原生限制。
## 功能通过是否意味着形式通过？
功能与形式分开统计。形式检查进一步报告16题性质违反，另外有截断和未决；这些反馈也说明分层检查能发现功能用例未触达的路径。
## 等待时限为什么有420和900两种？
MiniMax长请求导致多次停止，后段相同26题/组延长网络等待至900秒，单题总时限和输出上限保持。分项数据已经给出，历史420秒结果未被改写。
## 离线演示会收费吗？
不会。默认只回放本包原始记录，--verify使用本地Python裁判。真实CODESYS编译需要单独安装环境，本包默认按原日志核验；付费模型入口不会由离线工具调用。
## 为什么包含一个历史形式成功案例？
最新案例显示形式反馈将多泵性质违反从2条减少到1条；另外附有20261112历史实验中同类问题完全修复的真实案例。两者日期、裁判和用途明确标注，历史案例不进入最新成绩表。
'''}
    for name,body in docs.items():doc('02_说明',name,body)
    analysis=(s.MIRROR/'实验结果分析_20261113.md').read_text(encoding='utf-8');doc('04_数据与报告素材','实验结果分析_20261113',analysis)
    quote='''# 可引用成果表述
本项目实现了一个结合真实CODESYS编译、功能扫描测试与有界形式检查反馈的ST编程助手，形成需求输入、代码生成、分层验证、反馈修复及证据归档闭环。
在STBench-F1.4-P1的35题、两模型×两框架140题次对照中，自研DeepSeek通过33/35题（94.3%），其中公共题18/20、自建题15/15；Codex DeepSeek为34/35。MiniMax配置下，自研13/35、Codex11/35。两模型合计自研46/70、Codex45/70，本轮自研达到与Codex相近的总体水平，合计整题数略高。
反馈修复使自研新增14题通过，Codex新增10题；四组合计由首轮67/140提升至91/140。编译、功能和形式检查各自保留结果，展示了反馈修复的工程可行性。经过进一步调试与工程验证，助手有望用于工业现场辅助编程与程序校验。
引用数据时注明：每组35题946用例；FIFO原生限制单列；MiniMax420/900秒等待分项见数据表；功能整题通过率与形式有界检查分开统计。
'''
    doc('04_数据与报告素材','可引用成果表述',quote)
    doc('04_数据与报告素材','报告资料索引','''# 报告资料索引
- 结果主表.csv：四组首轮、最终、公共/自建、原生及修复增益。
- 逐题结果140.csv：每题名称、难度、来源、候选次数、结果、等待策略和原记录路径。
- 请求费用306.csv：306次请求与原始账本事件一一关联，含8条保留预留。
- 形式状态.csv、等待策略分项.csv：独立的形式分类与网络等待分项。
- 未通过题次.csv：后续优化定位；题库35题索引.csv：最新任务入口。
- 回归测试源码索引.csv：定位全部随包版本化测试源码；实际检查日志见05_实验记录。
- 可引用成果表述.html、实验结果分析_20261113.html：汇总文字和边界说明。
''')
    doc('03_PPT视频素材','演示操作卡','''# PPT与视频演示操作卡
1. 打开根目录00_先读我.html，展示四组结果和自研DeepSeek94.3%、自建15/15。
2. 打开Agent架构.svg，说明模型生成、真实编译、功能扫描、有界形式和反馈修复。
3. 打开案例/native/代码对照.html，展示编译失败→通过、功能0→21/21。
4. 打开案例/functional/代码对照.html，展示温控31/37→37/37与模型补丁。
5. 打开案例/formal/代码对照.html，展示功能12/12仍发现形式问题，并由2条减少至1条；需要完整形式成功展示时，使用明确标注历史日期的formal_legacy案例。
6. 双击06_离线工具/一键回放.cmd，或运行offline_demo.py --case all --verify；这是实际记录回放加本地功能复验，不调用生成模型。
7. 图表提供PNG和SVG，可直接用于PPT；总表、公共/自建、总体修复增益和形式状态分别呈现。原生编译以历史日志和指纹核验，不把本地功能解释执行说成现场PLC运行。
''')
    table='| 组别 | 首轮→最终 | 公共题 | 自建题 | 用例 |\n| --- | --- | --- | --- | --- |\n'
    for r in status['rows']:table+=f"| {r['label']} | {r['first_functional']}→{r['final_functional']}/35 | {r['groups']['public']['functional']}/20 | {r['groups']['self_built']['functional']}/15 | {r['assertions_passed']}/946 |\n"
    doc(Path('.'),'README_交接总览',f'''# Agent开发测试完整交接（2026-11-13）
本包只承担Agent开发与测试工程交接，供PPT/视频及报告汇总同学使用。首先打开00_先读我.html。

{table}

最新140题次306请求已完成并通过验收。自研两模型合计46/70、Codex45/70；反馈修复分别新增14与10题。原工程按Git提交{commit}导出，历史版本和本轮答卷均保留。
01_原工程保留源码、测试、文档与历史证据结构；为避免递归与重复体积，历史ZIP包不嵌套复制，排除清单给出路径和大小。本轮全部候选、原始传输及{counts['native_builds']}个真实编译工程另列05_实验记录。
02_说明包括环境、模块、数据口径、恢复、分工及答疑；03_PPT视频素材提供5组PNG/SVG图表、架构图与4个真实案例；04提供140题次、306请求等CSV；06提供零模型调用的标准库离线工具；07提供全文件指纹与验收结果。
预算上限480元，项目累计计入211.178859元，本次补齐新增28.551264元；8条异常预留2.643027元继续保留。模型密钥、DPAPI密文、安装包、许可证和编译缓存不在交付包中。
双击06_离线工具/一键核验.cmd，或运行python -B -X utf8 06_离线工具/verify_package.py --full，可以检查文件、成绩、费用、源码、原生证据及35题946参考用例。默认不调用模型、不重新编译CODESYS。建议解压到短路径。
''')
    for p in (SOURCE/'portable').glob('*.py'):copy(p,package/'06_离线工具'/p.name)
    text(package/'06_离线工具/一键回放.cmd','@echo off\nchcp 65001 >nul\npython -B -X utf8 "%~dp0offline_demo.py" --case all --verify\npause\n')
    text(package/'06_离线工具/一键核验.cmd','@echo off\nchcp 65001 >nul\npython -B -X utf8 "%~dp0verify_package.py" --full\npause\n')
    cards=''.join(f'<article><h3>{html.escape(m["label"])}</h3><p>{html.escape(m["source_label"])}</p><p>功能 {m["before"]["tests"]}/{m["total"]} → {m["after"]["tests"]}/{m["total"]}</p><a href="03_PPT视频素材/案例/{m["case"]}/代码对照.html">查看实际反馈与代码对照</a></article>' for m in metas)
    body=''.join(f'<tr><td>{r["label"]}</td><td>{r["first_functional"]}→{r["final_functional"]}/35</td><td>{r["groups"]["public"]["functional"]}/20</td><td>{r["groups"]["self_built"]["functional"]}/15</td><td>{r["assertions_passed"]}/946</td></tr>' for r in status['rows'])
    page=f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Agent最新开发测试交接包</title><style>body{{margin:0;background:#f2f6fa;color:#18364c;font:16px/1.8 system-ui,"Microsoft YaHei"}}main{{max-width:1180px;margin:auto;padding:30px 22px}}h1{{font-size:34px}}section{{background:white;border:1px solid #dce6ee;padding:26px;border-radius:15px;margin:24px 0}}a{{color:#087f7a}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(235px,1fr));gap:18px}}article{{background:#eef5f8;padding:20px;border-radius:12px}}.kpi{{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:16px}}.kpi div{{background:#173c56;color:white;border-radius:13px;padding:22px}}.kpi b{{font-size:30px;display:block}}table{{width:100%;border-collapse:collapse}}td,th{{padding:12px;border-bottom:1px solid #dbe6ee;text-align:left}}img{{width:100%;height:auto}}.note{{font-size:14px;color:#5e7487}}code{{background:#eef4f8;padding:3px 5px}}pre{{white-space:pre-wrap;background:#eef4f8;padding:18px}}</style></head><body><main>
<h1>Agent开发与测试成果交接</h1><p>2026-11-13最新版 · 原工程、完整证据与可复用素材 · 默认离线，不调用生成模型</p>
<div class="kpi"><div><b>140 / 140</b>题次完整归档</div><div><b>94.3%</b>自研DeepSeek · 33/35</div><div><b>46 vs 45</b>两框架合计通过题数 /70</div><div><b>+14题</b>自研反馈修复新增通过</div></div>
<section><h2>按分工领取资料</h2><div class="grid"><article><h3>PPT与视频</h3><a href="03_PPT视频素材/演示操作卡.html">演示操作卡</a><br><a href="03_PPT视频素材/Agent架构.svg">助手架构图</a><br><a href="03_PPT视频素材/图表/四组功能首轮与最终.png">结果图PNG</a><p>PNG/SVG图表、代码对照、真实回放齐全。</p></article><article><h3>报告汇总与汇报</h3><a href="04_数据与报告素材/报告资料索引.html">报告资料索引</a><br><a href="04_数据与报告素材/实验结果分析_20261113.html">完整结果分析</a><br><a href="04_数据与报告素材/可引用成果表述.html">可引用成果表述</a><p>140逐题、306请求费用、形式和等待策略分项均可追溯。</p></article><article><h3>开发接手与技术答疑</h3><a href="02_说明/工程结构与模块说明.html">模块与源码入口</a><br><a href="02_说明/环境搭建与运行.html">环境与离线运行</a><br><a href="02_说明/常见问题.html">常见问题</a><p>原结构源码、版本历史、测试与真实编译工程保留。</p></article></div></section>
<section><h2>最新四组结果</h2><p>自研在本轮两模型合计达到与Codex相近的总体水平，并多通过1题；DeepSeek自研公共18/20、自建15/15。</p><table><tr><th>组别</th><th>首轮→最终</th><th>公共题</th><th>自建题</th><th>功能用例</th></tr>{body}</table><p class="note">功能每组35题946用例，原生分母34。MiniMax前9题/组等待420秒、后26题/组900秒，两个框架的后26题集合相同。形式结果独立记录。</p><img src="03_PPT视频素材/图表/四组功能首轮与最终.png" alt="四组功能成绩"><img src="03_PPT视频素材/图表/公共题与自建题.png" alt="公共与自建分项"></section>
<section><h2>真实案例与离线演示</h2><div class="grid">{cards}</div><pre>python -B -X utf8 06_离线工具/offline_demo.py --case all --verify
python -B -X utf8 06_离线工具/verify_package.py --full</pre><p>默认回放实际记录；--verify重新运行功能裁判。历史形式成功案例与最新主表明确分开。</p></section>
<section><h2>完整证据入口</h2><p><a href="README_交接总览.html">交接总览</a> · <a href="04_数据与报告素材/结果主表.csv">结果CSV</a> · <a href="04_数据与报告素材/逐题结果140.csv">140逐题CSV</a> · <a href="04_数据与报告素材/请求费用306.csv">306请求CSV</a> · <a href="04_数据与报告素材/形式状态.csv">形式状态</a> · <a href="04_数据与报告素材/等待策略分项.csv">等待策略</a></p><p><a href="05_实验记录/最新正式实验/final_audit.json">正式验收</a> · <a href="07_清单指纹/原生编译索引.json">{counts['native_builds']}个真实编译工程索引</a> · <a href="07_清单指纹/文件清单.json">文件SHA256清单</a></p><p class="note">源码Git提交：{commit}。项目计入211.178859/480元，其中本批保留8条异常预留2.643027元。完整证据与旧版本保持，不包含API密钥和许可证。</p></section></main></body></html>'''
    text(package/'00_先读我.html',page)


def check_links(package):
    from html.parser import HTMLParser
    from urllib.parse import unquote,urlsplit
    class Links(HTMLParser):
        def __init__(self):super().__init__();self.links=[]
        def handle_starttag(self,tag,attrs):
            self.links.extend(v for k,v in attrs if k in ('href','src') and v)
    pages=[package/'00_先读我.html',package/'README_交接总览.html']
    for folder in ('02_说明','03_PPT视频素材','04_数据与报告素材'):pages.extend((package/folder).rglob('*.html'))
    checked=0
    for page in pages:
        parser=Links();parser.feed(page.read_text(encoding='utf-8'))
        for value in parser.links:
            parts=urlsplit(value)
            if parts.scheme or parts.netloc or not parts.path:continue
            target=(page.parent/unquote(parts.path)).resolve()
            assert target.is_relative_to(package.resolve()) and target.exists(),(page,value)
            checked+=1
    return dict(passed=True,html_pages=len(pages),local_links=checked)


def manifest(package,commit,counts):
    target=package/'07_清单指纹/文件清单.json'
    files={p.relative_to(package).as_posix():dict(bytes=p.stat().st_size,sha256=sha(p)) for p in sorted(package.rglob('*')) if p.is_file() and p!=target}
    js(target,dict(package=NAME,source_commit=commit,counts=counts,files=files,manifest_self_excluded=True))
    return files


def validate(package,work):
    relocated=work/'relocated'/NAME;shutil.copytree(package,relocated)
    env=dict(os.environ,PYTHONUTF8='1',PYTHONDONTWRITEBYTECODE='1',PYTHONNOUSERSITE='1',PYTHONPATH='')
    for key in list(env):
        if 'API_KEY' in key.upper() or key.upper() in ('GH_TOKEN','GITHUB_TOKEN'):env.pop(key,None)
    scripts=relocated/'06_离线工具'
    commands=[[sys.executable,'-B','-X','utf8',str(scripts/'verify_package.py'),'--full'],
        [sys.executable,'-B','-X','utf8',str(scripts/'offline_demo.py'),'--case','formal_legacy','--formal-check']]
    logs=[]
    for command in commands:
        result=subprocess.run(command,cwd=work,capture_output=True,text=True,encoding='utf-8',env=env,timeout=240)
        logs.append(result.stdout+'\n'+result.stderr)
        assert result.returncode==0,logs[-1][-4000:]
    return '\n\n'.join(logs)


def build(tag,commit):
    work=Path('E:/PLC_Dev/evidence/handoff_agent_20261113')/tag
    assert not work.exists(),'Never overwrite an earlier build'
    cfg=s.config();root=Path(cfg['campaign_root']);plan=s.load(root/'study_plan.json')
    assert s.load(root/'completion.json')['completed'] and s.load(root/'final_audit.json')['passed']
    ledger=Path(cfg['budget_ledger_path']);ledger_before=ledger.read_bytes()
    assert (s.load(ledger)['spent_cny'],len(s.load(ledger)['events']))==(211.178859,1965)
    commit=subprocess.check_output(['git','rev-parse',commit],cwd=REPO,text=True).strip()
    work.mkdir(parents=True);package=work/NAME;package.mkdir()
    print('EXPORT committed source',commit,flush=True);source_count,excluded=export_source(package,work,commit)
    print('EXPORT 140 records, raw transport and native projects',flush=True)
    records,origins,native_count,native_excluded=export_evidence(package,cfg,root,plan)
    assert native_count==205
    status,test_count=tables(package,cfg,root,records,origins);metas=case_materials(package,records)
    counts=dict(source_files=source_count,tasks=35,reference_cases=946,study_jobs=140,requests=306,new_requests=263,
        imported_requests=43,native_builds=native_count,regression_test_methods_indexed=test_count,real_case_examples=4)
    print('RENDER guides and reusable charts',flush=True);guides(package,status,metas,commit,counts);charts(package,status)
    js(package/'07_清单指纹/排除清单.json',dict(source_archives=excluded,native_rebuildable_cache=native_excluded,
        note='Original repository archives remain preserved at their original locations. No credential stores, installed software or licenses are copied.'))
    js(package/'07_清单指纹/来源与交付信息.json',dict(source_commit=commit,git_remote='https://github.com/WtqMyou/plc-st-coding-agent',
        dataset='STBench-F1.4-P1',completed_at=s.load(root/'completion.json')['at'],counts=counts,
        built_at=s.stamp(),original_acceptance_archive_sha256=sha(s.MIRROR/'验收包.zip'),
        project_ledger_sha256=hashlib.sha256(ledger_before).hexdigest(),
        latest_release='progress/f14_agent_v14/release',legacy_formal_case_release='progress/f14_candidate/release',
        exclusions='Historical ZIP duplication; native .compileinfo/.precompilecache/.opt; credentials, licenses and installed software'))
    manifest(package,commit,counts)
    js(package/'07_清单指纹/网页链接检查.json',check_links(package))
    print('SCAN known credentials and nested archive content',flush=True)
    js(package/'07_清单指纹/凭据检查.json',prior.scan(package));manifest(package,commit,counts)
    print('VALIDATE relocated package without keys or external runtime paths',flush=True)
    log=validate(package,work);text(package/'07_清单指纹/离线验收输出.log',log)
    assert ledger.read_bytes()==ledger_before,'Handoff must not change the experiment ledger'
    text(package/'07_清单指纹/交接验收记录.md','# 最新交接包验收\n\n独立解压位置、不同工作目录、移除API密钥后，通过全部文件指纹、冻结代码、140题次/306请求/费用、精确补丁重放、205原生编译工程关联核验；35题参考功能复验946/946，四个案例功能复验及历史案例有界形式复验均通过。HTML相对链接和凭据检查通过。构建与验收模型调用0次；原1965条事件、211.178859元账本字节保持不变。\n\n离线完整输出见离线验收输出.log；模型生成记录与本地复验分开，原生结果使用原始日志与指纹。\n')
    files=manifest(package,commit,counts)
    destination=REPO/'progress'/('Agent开发测试完整交接包_20261113'+('' if tag=='v1' else '_'+tag)+'.zip')
    assert not destination.exists(),'Never overwrite a delivered archive'
    print('ARCHIVE',len(files)+1,'files',flush=True)
    with zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for path in sorted(package.rglob('*')):
            if path.is_file():archive.write(path,NAME+'/'+path.relative_to(package).as_posix())
    with zipfile.ZipFile(destination) as archive:assert archive.testzip() is None
    receipt=dict(archive=destination.name,sha256=sha(destination),bytes=destination.stat().st_size,package_files=len(files)+1,
        source_commit=commit,counts=counts,portable_validation_passed=True,model_requests_during_build=0,
        ledger_unchanged=True,unpacked_preview=(package/'00_先读我.html').as_posix(),manifest_sha256=sha(package/'07_清单指纹/文件清单.json'))
    js(destination.with_suffix('.manifest.json'),receipt);js(work/'build_receipt.json',receipt)
    assert ledger.read_bytes()==ledger_before
    print(json.dumps(receipt,ensure_ascii=False),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--tag',default='v1');parser.add_argument('--source-commit',default='HEAD')
    args=parser.parse_args();assert re.fullmatch(r'v[0-9]+',args.tag);build(args.tag,args.source_commit)

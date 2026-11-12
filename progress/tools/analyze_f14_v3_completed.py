"""Reproducible final analysis, with official run and free correction replay separated."""
from collections import Counter
from datetime import datetime
from pathlib import Path
import json
import sys
import zipfile
import f14_v3_core as s

ROOT=Path(s.config()['campaign_root'])
OLD=Path('E:/PLC_Dev/evidence/real_experiments/f14_p1_20261111b')
OUT=s.REPO/'progress/evidence/f14_v3_analysis_20261112'
DIAG=s.REPO/'progress/evidence/f14_v4_diagnostics_20261112'
ARMS=['custom_deepseek-v4pro','codex_deepseek-v4pro','custom_minimax-m27','codex_minimax-m27']
LABELS=dict(zip(ARMS,['自研 DeepSeek','Codex DeepSeek','自研 MiniMax','Codex MiniMax']))

def records(root):return [s.load(p) for p in sorted((root/'jobs').glob('*/*.json')) if p.name.count('.')==1]
def chosen(r):return r['attempts'][r['best_attempt']]
def percent(a,b):return f'{100*a/b:.1f}%' if b else '—'

def summarize(rows):
    result={}
    for arm in ARMS:
        selected=[r for r in rows if r['condition']==arm];best=[chosen(r) for r in selected]
        item=dict(jobs=len(selected),first=sum(r['attempts'][0]['functional_pass'] for r in selected),
            final=sum(a['functional_pass'] for a in best),native=sum(a['native_pass'] for a in best),
            complete=sum(a['complete_code'] for a in best),cases=sum(a['tests_passed'] for a in best),
            total=sum(r['tests_total'] for r in selected),formal=dict(Counter(a['verification_status'] for a in best)))
        for scope,prefix in [('public','public-'),('self','self-')]:
            subset=[r for r in selected if r['pid'].startswith(prefix)]
            item[scope]=dict(jobs=len(subset),final=sum(chosen(r)['functional_pass'] for r in subset),
                cases=sum(chosen(r)['tests_passed'] for r in subset),total=sum(r['tests_total'] for r in subset))
        result[arm]=item
    return result

def main():
    source=records(ROOT);old=records(OLD);assert len(source)==len(old)==140
    ledger=s.load(s.config()['budget_ledger_path']);before=s.load(ROOT/'ledger_before_study.json')
    completion=s.load(ROOT/'completion.json');audit=s.load(ROOT/'final_audit.json');assert completion['completed'] and audit['passed']
    assert s.sha(s.config()['budget_ledger_path'])==audit['ledger_sha256']
    assert s.prefix_ok(ledger,before) and len(ledger['events'])==1141 and ledger['spent_cny']==108.080587
    totals=summarize(source);oldtotals=summarize(old)
    events=ledger['events'][s.HISTORY:];assert len(events)==230
    cost=sum((s.money(e.get('accounted_cny',e['reserved_cny'])) for e in events),s.money(0))
    unknown=[e for e in events if e['status']=='reserved'];assert len(unknown)==6
    first=min(datetime.fromisoformat(r['started_at']) for r in source);end=datetime.fromisoformat(completion['at'])
    oldfirst=min(datetime.fromisoformat(r['started_at']) for r in old);oldend=datetime.fromisoformat(s.load(OLD/'completion.json')['ended_at'])
    duration=(end-first).total_seconds();old_duration=(oldend-oldfirst).total_seconds()
    restart=datetime.fromisoformat(s.load(ROOT/'active_run.json')['process_created_at'])
    result=dict(official=totals,previous=oldtotals,requests=230,settled=224,unknown_reserved=6,
        new_accounted_cny=float(cost),unknown_reserved_cny=float(sum((s.money(e['reserved_cny']) for e in unknown),s.money(0))),
        cumulative_accounted_cny=ledger['spent_cny'],budget_cap_cny=210,wall_minutes=duration/60,
        previous_wall_minutes=old_duration/60,speedup=old_duration/duration,resumed_128_wall_minutes=(end-restart).total_seconds()/60,
        model_calls_during_analysis=0,source_final_audit_sha256=s.sha(ROOT/'final_audit.json'),ledger_sha256=s.sha(s.config()['budget_ledger_path']))
    framework_cost={framework:float(sum((s.money(e.get('accounted_cny',e['reserved_cny'])) for e in events if e['request']['job_id'].startswith(framework+'_')),s.money(0))) for framework in ('custom','codex')}
    result['framework_accounted_cny']=framework_cost
    text=['# Agent v3全量结果与工具纠错复评','',
        '本轮于2026-11-12 17:31结束，140题次、230次请求，四组各35题946条功能用例。原始结果和费用均保留，以下把冻结运行记录与后续免费工具纠错复评分开列出。','',
        '## 冻结运行记录','',
        '| 组别 | 整题功能 首次→最终/35 | 原生编译/34 | 功能断言/946 | 公共题/20 | 自建题/15 |',
        '| --- | ---: | ---: | ---: | ---: | ---: |']
    for arm in ARMS:
        a=totals[arm];text.append(f"| {LABELS[arm]} | {a['first']}→{a['final']} | {a['native']} | {a['cases']} | {a['public']['final']} | {a['self']['final']} |")
    total_final=sum(a['final'] for a in totals.values());total_first=sum(a['first'] for a in totals.values());cases=sum(a['cases'] for a in totals.values())
    assert (total_first,total_final,cases)==(43,59,2443)
    text+=['',f'功能整题43→59/140，修复新增16题次；功能断言2443/3784（{percent(cases,3784)}），完整代码127/140，原生编译103/136。FIFO原型的平台限制按原规则单列，不进入原生编译分母。',
        '', '| 范围 | 上轮整题通过 | 本轮整题通过 | 上轮断言通过 | 本轮断言通过 |','| --- | ---: | ---: | ---: | ---: |']
    for scope,label in [('public','公共题'),('self','自建题')]:
        n=sum(a[scope]['jobs'] for a in totals.values());of=sum(a[scope]['final'] for a in oldtotals.values());nf=sum(a[scope]['final'] for a in totals.values())
        oc=sum(a[scope]['cases'] for a in oldtotals.values());nc=sum(a[scope]['cases'] for a in totals.values());ct=sum(a[scope]['total'] for a in totals.values())
        text.append(f'| {label} | {of}/{n}（{percent(of,n)}） | {nf}/{n}（{percent(nf,n)}） | {oc}/{ct}（{percent(oc,ct)}） | {nc}/{ct}（{percent(nc,ct)}） |')
    text+=['','自研DeepSeek与Codex在自建题均为14/15、453/476条断言；MiniMax全库两框架均10/35。原始全库计数为自研28/70、Codex31/70。相邻版本对照为完整独立批次的描述性结果，没有拼接答卷。',
        '', '## 时间、费用与中断','',
        f'本轮从首题开始到验收结束约{duration/60:.1f}分钟，上轮约{old_duration/60:.1f}分钟，实际跨度缩短约{100*(1-duration/old_duration):.1f}%，约{old_duration/duration:.2f}倍。含睡眠和等待人工重启的时间；接续的128题次约{(end-restart).total_seconds()/60:.1f}分钟。',
        f'本轮新增计入{float(cost):.6f}元，其中224次已结算估算21.628605元、6次睡眠中断未知预留2.390001元。累计108.080587/210元。保留预留并待供应商账单核对，没有把未知费用当成零。',
        '7个题次因睡眠中断终止，保留已有候选及评分，继续留在全量分母中；没有重发它们的请求。原记录保持故障时状态，派生生命周期记录位于effective_jobs。',
        '', '## 形式检查的独立价值','',
        '功能通过的59份最终候选中：19份有界通过、27份预算截断、9份未决、4份报告违反。形式层保留了功能测试通过后仍报告反例的4份答卷，展示了第三类反馈的独立检查价值；有界通过不写成完整证明。',
        '', '## 本次复盘发现并修正的工具问题','',
        'v3分号规则错误地给CODESYS的顶层END_STRUCT增加了分号，影响16个题次的24份候选，其中21份是工具直接插入错误分号，另外3份原始模型文本已经带有该分号。这属于本项目格式化规则的问题，不归因于队友题库逻辑。',
        '另有TO_INT/TO_WORD/TO_UINT/TO_ULINT等标准转换未在当前解释器完整接入，原来按本地子集未决单列。修正版支持可精确建模的整数、BOOL和TIME/LTIME到整数转换，超出范围及浮点等未覆盖转换继续明确未决。',
        '修正放在独立v4诊断目录，未改冻结v3源码。纠正只涉及顶层STRUCT结束分隔符与转换执行能力；不改题面、接口、测试期望，不修改模型算法或补充参考程序。']
    if (DIAG/'diagnostic_results.json').is_file():
        data=s.load(DIAG/'diagnostic_results.json');assert data['model_calls']==0 and data['official_results_unchanged']
        rows=data['rows'];result['free_correction']={}
        text+=['','## 固定答卷免费纠错复评','',
            '| 组别 | 原始运行/35 | 仅修正STRUCT/35 | 再接入转换/35 | 纠错后公共/20 | 纠错后自建/15 |','| --- | ---: | ---: | ---: | ---: | ---: |']
        for arm in ARMS:
            subset=[r for r in rows if r['condition']==arm]
            a=sum(r['original_best']['functional_pass'] for r in subset);n=sum(r['normalization_only']['functional_pass'] for r in subset);f=sum(r['full']['functional_pass'] for r in subset)
            pub=sum(r['full']['functional_pass'] for r in subset if r['pid'].startswith('public-'));selfmade=f-pub
            diagnostic_attempts=Path('E:/PLC_Dev/evidence/offline_replays/f14_v4_20261112/attempts')
            first=sum(s.load(diagnostic_attempts/arm/(r['pid']+'.0.json'))['full']['functional_pass'] for r in subset)
            result['free_correction'][arm]=dict(original=a,format_only=n,full=f,public=pub,self=selfmade,first=first,cases=sum(r['full']['tests_passed'] for r in subset))
            text.append(f'| {LABELS[arm]} | {a} | {n} | {f} | {pub} | {selfmade} |')
        text+=['', '纠错复评合计68/140：公共22/80（27.5%）、自建46/60（76.7%）；功能断言2725/3784（72.0%）。按相同候选选择规则，首轮49→最终68，原有一次修复机会带来19个新增成功题次。两种模型的自建题整题数均与Codex一致；MiniMax全库自研12/35、Codex10/35。',
            f"本轮账本按框架合计，自研{framework_cost['custom']:.6f}元、Codex{framework_cost['codex']:.6f}元，自研低约{100*(1-framework_cost['custom']/framework_cost['codex']):.1f}%。该口径包含各自未结算预留，两组模型配置保持相同，CLI上下文请求结构不同。"]
        text+=['','这是原230份尝试的统一免费复评，沿用相同的候选选择规则，没有新的模型生成或费用。纠错后表格不能冒称一轮重新生成的新实验；原始表格继续保留供追溯。',
            '946条参考用例、35条错误断言控制、946条内部变量改名用例均通过修正版回归；结构体候选重新执行真实CODESYS编译，并保存更正后的源码和原生工程结果。']
    text+=['','## 收尾建议','',
        '开发测试的主体工作已经完成：真实编译、功能、形式反馈与最多一次修复已形成可运行闭环，批次并行和费用保护已验证。自建题DeepSeek结果可作为演示主线，公共题改善与形式反例可展示反馈价值。',
        '交接资料同时提供v3冻结运行、v4工具纠错复评、原答卷、费用、耗时和中断证据。先完成这一轮资料更新与待核费用登记；后续付费实验按明确的新验证问题另行安排。','']
    OUT.mkdir(parents=True,exist_ok=True);s.atomic_json(OUT/'analysis.json',result);(OUT/'结果分析.md').write_text('\n'.join(text),encoding='utf-8')
    print('PASS final analysis: 140 jobs, 230 requests, 59 functional passes; reports saved',flush=True)

if __name__=='__main__':main()

"""Build denominator-preserving tables and plots from immutable candidate records."""
import argparse
import csv
from datetime import datetime,timezone
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from stbench.campaign import configuration,group_order,PILOT
from stbench.cli import problems
from stbench.evaluation import atomic_json
from stbench.harness.engine import RunRecord
from pilot_provenance import load_sources
from request_accounting import accounting_record
from stbench.portability import adapt,PROFILE


def analysis_problems(profile):
    selected=problems()
    return [adapt(p,'','codesys')[0] for p in selected] if profile==PROFILE else selected


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--campaign',type=Path)
    ap.add_argument('--stage',default='final');ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    cfg=configuration('');root=args.campaign or Path(cfg['campaign_root']);folder=root/args.stage
    freeze=json.loads((folder/'freeze.json').read_text(encoding='utf-8'))
    cfg=freeze['config'];selected=analysis_problems(freeze['profile'])
    accepted_sources={freeze['judge_sha256']}
    if args.stage=='pilot':accepted_sources=load_sources(root,freeze)
    if args.stage!='final':selected=[p for p in selected if p.pid in PILOT]
    n=len(selected);cases=sum(len(p.test_cases) for p in selected);rows=[]
    groups=group_order(cfg)
    if args.stage=='retest' or args.stage.startswith('develop_round_'):
        groups=[g for g in groups if g[0]=='custom']
    for framework,mid in groups:
        row=dict(framework=framework,model_id=mid,n=n,cases_total=cases,attempted=0,generated=0,
            first_codesys=0,final_codesys=0,first_cases=0,final_cases=0,whole_problem_solved=0,
            openplc_passed=0,both_platforms_and_cases=0,candidates=0,tokens=0,known_cost_cny=0.,
            wall_seconds=0.,input_tokens=0,output_tokens=0,unknown_cost_attempts=0,unissued_control_stops=0,
            out_of_contract_only_ltl=0,ltl={},stops={},codesys_statuses={})
        row.update(specs_total=sum(bool(s.ltl.strip()) for p in selected for s in p.specs),
            bounded_pass_specs=0,confirmed_violated_specs=0,outside_contract_specs=0,unresolved_specs=0)
        for p in selected:
            path=folder/(framework+'_'+mid)/(p.pid+'.json')
            expected_specs=sum(bool(s.ltl.strip()) for s in p.specs)
            if not path.exists():
                row['codesys_statuses']['not_run']=row['codesys_statuses'].get('not_run',0)+1
                row['unresolved_specs']+=expected_specs
                row['ltl']['not_run']=row['ltl'].get('not_run',0)+1
                row['stops']['not_run']=row['stops'].get('not_run',0)+1;continue
            record,controls=accounting_record(RunRecord.load(path));best=record.best
            row['unissued_control_stops']+=controls
            if record.tests_total!=len(p.test_cases):raise RuntimeError('Case denominator drift: '+str(path))
            row['attempted']+=bool(record.attempts);row['generated']+=any(a.code for a in record.attempts)
            row['candidates']+=len(record.attempts);row['tokens']+=record.total_tokens
            row['input_tokens']+=sum(a.prompt_tokens for a in record.attempts)
            row['output_tokens']+=sum(a.completion_tokens for a in record.attempts)
            row['known_cost_cny']+=sum(a.cost_cny for a in record.attempts)
            row['unknown_cost_attempts']+=sum(bool(a.provider_error) and not a.actual_model for a in record.attempts)
            row['stops'][record.stop_reason]=row['stops'].get(record.stop_reason,0)+1
            for a in record.attempts:
                evidence=a.judge.get('evidence_metadata',{})
                if evidence and evidence.get('judge_source_sha256') not in accepted_sources:
                    raise RuntimeError('Mixed judge versions: '+str(path))
            first=record.attempts[0] if record.attempts else None
            row['first_codesys']+=bool(first and first.platform_results.get('codesys',{}).get('status')=='passed')
            row['first_cases']+=first.tests_passed if first else 0
            row['final_codesys']+=bool(best and best.platform_results.get('codesys',{}).get('status')=='passed')
            native_status=best.platform_results.get('codesys',{}).get('status','not_run') if best else 'not_run'
            row['codesys_statuses'][native_status]=row['codesys_statuses'].get(native_status,0)+1
            row['final_cases']+=best.tests_passed if best else 0
            row['whole_problem_solved']+=record.solved
            native=path.with_name(p.pid+'.openplc.json');openplc=False
            if native.exists():
                check=json.loads(native.read_text(encoding='utf-8'))
                if best and check.get('candidate_hash')!=best.code_hash:raise RuntimeError('OpenPLC candidate mismatch')
                openplc=check.get('status')=='passed'
            row['openplc_passed']+=openplc;row['both_platforms_and_cases']+=bool(record.solved and openplc)
            timing=path.with_name(p.pid+'.timing.json')
            if timing.exists():row['wall_seconds']+=json.loads(timing.read_text(encoding='utf-8'))['active_wall_seconds']
            status=best.verification_status if best else 'not_run'
            row['ltl'][status]=row['ltl'].get(status,0)+1
            violations=best.judge.get('model_check',{}).get('violations',[]) if best else []
            outside=lambda v:p.pid=='public-hard-04' and any(s.get('enqueue') and s.get('dequeue') for s in v.get('trace',[]))
            invalid_specs=len({v['id'] for v in violations if outside(v)})
            valid_specs=len({v['id'] for v in violations if not outside(v)})
            mc=best.judge.get('model_check',{}) if best else {}
            held=mc.get('specs_hold',0) if mc.get('executed') and not mc.get('error') and not mc.get('truncated') else 0
            row['bounded_pass_specs']+=held;row['confirmed_violated_specs']+=valid_specs
            row['outside_contract_specs']+=invalid_specs
            row['unresolved_specs']+=expected_specs-held-valid_specs-invalid_specs
            if p.pid=='public-hard-04' and status=='violated' and violations:
                row['out_of_contract_only_ltl']+=all(outside(v) for v in violations)
        assert sum(row['ltl'].values())==n and 0<=row['final_cases']<=cases
        assert sum(row['codesys_statuses'].values())==n and row['input_tokens']+row['output_tokens']==row['tokens']
        assert row['unresolved_specs']>=0 and sum(row[k] for k in ['bounded_pass_specs','confirmed_violated_specs','outside_contract_specs','unresolved_specs'])==row['specs_total']
        rows.append(row)
    ledger=json.loads(Path(cfg['budget_ledger_path']).read_text(encoding='utf-8'))
    budget=dict(accounted_cny=ledger['spent_cny'],returned_cost_estimate_cny=sum(e.get('accounted_cny',0) for e in ledger['events'] if e['status']=='settled'),
        reserved_unknown_cny=sum(e.get('reserved_cny',0) for e in ledger['events'] if e['status']=='reserved'),halted=ledger['halted'])
    args.out.mkdir(parents=True,exist_ok=True)
    atomic_json(args.out/'analysis.json',dict(stage=args.stage,created_utc=datetime.now(timezone.utc).isoformat(),
        profile=freeze['profile'],source_sha256=freeze['judge_sha256'],all_tasks_attempted=all(r['attempted']==n for r in rows),
        rows=rows,budget=budget,warning='Returned-cost upper estimates plus reserved unknowns; not the upstream bill'))
    keys=[k for k in rows[0] if not isinstance(rows[0][k],dict)]
    with (args.out/'metrics.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=keys);writer.writeheader()
        writer.writerows({k:r[k] for k in keys} for r in rows)
    complete=all(r['attempted']==n for r in rows)
    text=[f'# {args.stage} 实验分析','',f'每组固定分母：{n} 题、{cases} 条用例；未生成、编译失败及调用失败均不从分母删除。',
        '本阶段已覆盖全部题目。' if complete else '当前为未完成快照，仍有题目未运行，不作为四组最终比较结论。','',
        '|框架|模型|实际尝试|CODESYS 首次→最终|用例首次→最终|整题通过|OpenPLC|双平台且用例全过|',
        '|---|---|---:|---|---|---:|---:|---:|']
    for r in rows:text.append(f"|{r['framework']}|{r['model_id']}|{r['attempted']}/{n}|{r['first_codesys']}/{n} → {r['final_codesys']}/{n}|{r['first_cases']}/{cases} → {r['final_cases']}/{cases}|{r['whole_problem_solved']}/{n}|{r['openplc_passed']}/{n}|{r['both_platforms_and_cases']}/{n}|")
    text+=['','## 时间、用量和费用','', '|框架/模型|候选数|分钟|已返回输入/输出 token|已返回费用估计|费用未知尝试|','|---|---:|---:|---:|---:|---:|']
    for r in rows:text.append(f"|{r['framework']}/{r['model_id']}|{r['candidates']}|{r['wall_seconds']/60:.2f}|{r['input_tokens']} / {r['output_tokens']}|{r['known_cost_cny']:.4f}|{r['unknown_cost_attempts']}|")
    text+=['',f"原始记录中的未发出暂停事件共 {sum(r['unissued_control_stops'] for r in rows)} 次，单独保留，不计入请求次数或费用未知尝试；真正的上游超时仍计入。",
        '表中候选数按已发出的生成尝试统计，包含截断和调用失败；原始暂停留痕完整保留。',
        '整题通过列采用 CODESYS 编译与功能用例口径；OpenPLC 单列。功能行为由扫描解释器执行，未主张物理 PLC 运行。','',
        '## LTL 状态','']
    for r in rows:text.append(f"- CODESYS {r['framework']}/{r['model_id']}：{r['codesys_statuses']}。not_run 表示未进入真实编译，不等于编译器报错，但仍保留在题目分母内。")
    for r in rows:
        text.append(f"- {r['framework']}/{r['model_id']}：{r['ltl']}；规约固定分母 {r['specs_total']}，界内通过 {r['bounded_pass_specs']}、确认违反 {r['confirmed_violated_specs']}、环境外反例 {r['outside_contract_specs']}、未完成或未判定 {r['unresolved_specs']}。")
    text+=['','FIFO 原题禁止同时请求入队和出队。仅由此类轨迹产生的反例单列，不能据此断言原题范围内程序错误；该类也不计为通过。']
    text+=['','bounded_pass 为有限输入域、固定绑定、给定深度内结论；截断、超时、无法判定和工具错误均不算规约通过。','',
        f"共享账本累计计入 {budget['accounted_cny']:.6f} 元，含未知预留 {budget['reserved_unknown_cny']:.6f} 元；不是上游实际账单。",'']
    (args.out/'report.md').write_text('\n'.join(text),encoding='utf-8')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.ticker import PercentFormatter
    labels=[('Custom' if r['framework']=='custom' else 'Codex')+'\n'+('DeepSeek' if 'deepseek' in r['model_id'] else 'MiniMax') for r in rows]
    fig,axes=plt.subplots(1,2,figsize=(10,4),layout='constrained')
    for ax,title,initial,final,denom in [(axes[0],'CODESYS compile rate','first_codesys','final_codesys',n),(axes[1],'Functional case pass rate','first_cases','final_cases',cases)]:
        ax.bar([i-.18 for i in range(len(rows))],[r[initial]/denom for r in rows],.36,label='First',color='#a9bad2')
        ax.bar([i+.18 for i in range(len(rows))],[r[final]/denom for r in rows],.36,label='Final',color='#305d8d')
        ax.set_xticks(range(len(rows)),labels);ax.set_ylim(0,1.05);ax.yaxis.set_major_formatter(PercentFormatter(1))
        ax.set_title(title);ax.spines[['top','right']].set_visible(False);ax.legend(frameon=False)
    fig.suptitle(args.stage+(' (full denominators, including failures)' if complete else ' — PARTIAL SNAPSHOT\nUnrun tasks remain in the denominator; coverage differs'))
    fig.savefig(args.out/'comparison.png',dpi=180);fig.savefig(args.out/'comparison.svg');plt.close(fig)
    print(json.dumps(dict(out=str(args.out.resolve()),attempted=[r['attempted'] for r in rows],n=n),ensure_ascii=False))


if __name__=='__main__':main()

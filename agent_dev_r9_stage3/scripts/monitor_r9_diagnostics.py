"""Read-only progress and final diagnostic interpretation; zero model calls."""
import json
from pathlib import Path
import re
import sys
import time
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from stbench.campaign import configuration,tasks,group_order,first_candidate_bound,digest
from stbench.evaluation import atomic_json
from r9_diagnostics import status,summarize
from campaign_status import load


def finish(cfg):
    root=Path(cfg['campaign_root']);plan=load(root/'diagnostic_plan.json')
    summarize(cfg,plan);summary=load(root/'diagnostic_summary.json');responses=[]
    for p in sorted((root/'jobs').glob('*/*.response.json')):
        data=load(p);message=data.get('message',{});content=message.get('content') or ''
        thoughts=message.get('reasoning_content') or ''
        tags=re.findall(r'<think>(.*?)</think>',content,re.S)
        responses.append(dict(condition=p.parent.name,pid=p.name[:-len('.response.json')],
            finish_reason=data.get('finish_reason'),content_characters=len(content),reasoning_characters=len(thoughts),
            tagged_thinking_characters=sum(map(len,tags)),unclosed_think=content.lstrip().startswith('<think>') and '</think>' not in content,
            contains_end_function_block='END_FUNCTION_BLOCK' in content.upper()))
    rows=summary['rows'];delta={}
    for fw in ('custom','codex'):
        own={r['variant']:r for r in rows if r['framework']==fw}
        delta[fw]=dict(generated=own['concise']['generated']-own['baseline']['generated'],
                       solved=own['concise']['solved']-own['baseline']['solved'])
    complete=all(r['attempted']==6 for r in rows)
    benefit=complete and all(v['generated']>=0 and v['solved']>=0 for v in delta.values()) and any(v['generated']>0 or v['solved']>0 for v in delta.values())
    specs={m['id']:m for m in cfg['models']}
    upper=sum(first_candidate_bound(specs[mid],p,cfg,fw) for _,p,_ in tasks() for fw,mid in group_order(cfg))
    ledger=load(cfg['budget_ledger_path']);remaining=75-ledger['spent_cny']
    gate=dict(diagnostic_complete=complete,prompt_benefit_observed=benefit,changes=delta,
        source_sha256=digest(),remaining_total_cny=remaining,full_first_candidate_upper_cny=upper,
        full_formal_run_started=False,ready_for_full_formal_run=False,
        reasons=['This is a single-candidate MiniMax prompt diagnosis, not a real repair-policy comparison',
                 'New full four-condition evaluation needs its own frozen protocol and budget feasibility check'],
        next_step='Review saved response structure and paired results before changing transport or generation limits',
        automatic_paid_requests=0)
    atomic_json(root/'response_structure_analysis.json',responses);atomic_json(root/'r9_gate.json',gate)
    lines=['# 小规模诊断结果','', '固定六题、MiniMax、实际 Codex CLI 与自研两框架；两种提示各一个候选。不能替代四组全量实验。','',
           '|框架|提示|已尝试/6|取得代码|整题功能通过|截断/空回复|','|---|---|---|---|---|']
    for r in rows:lines.append(f"|{r['framework']}|{r['variant']}|{r['attempted']}|{r['generated']}|{r['solved']}|{r['incomplete']}|")
    lines+=['',f"本轮累计计入增量 {summary['additional_accounted_cny']:.4f}/10 元（含预留口径），共享账本 {ledger['spent_cny']:.4f}/75 元。",'',
            f"提示改进在本样本是否观察到无退步的正收益：{benefit}。单次小样本不证明稳定优势。",'',
            f"当前全量首候选的保守预留约 {upper:.2f} 元，总剩余额度约 {remaining:.2f} 元；未自动开启全量 R9。",'',
            '响应结构明细见 response_structure_analysis.json；下一阶段门槛见 r9_gate.json。', '']
    (root/'诊断结果.md').write_text('\n'.join(lines),encoding='utf-8')


def main():
    cfg=configuration(str(ROOT/'config.r9_diagnostic.json'));root=Path(cfg['campaign_root'])
    while True:
        alive,terminal=status(cfg)
        if terminal:
            finish(cfg);return 0
        if not alive and load(root/'active_run.json'):
            atomic_json(root/'diagnostic_state.json',dict(state='stopped',error='Registered runner disappeared; retained reservations need diagnosis'))
            finish(cfg);status(cfg);return 2
        time.sleep(15)


if __name__=='__main__':raise SystemExit(main())

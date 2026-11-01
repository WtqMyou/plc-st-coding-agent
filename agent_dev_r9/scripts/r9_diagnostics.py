"""Six-task MiniMax prompt diagnosis; fixed additional cap, no automatic full R9 run."""
import argparse
from contextlib import ExitStack
import ctypes
from datetime import datetime,timezone
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
import sys
import time
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from stbench.campaign import configuration,credentials,credential_check,digest,PILOT,native_preflight,tasks,first_candidate_bound
from stbench.billing import CampaignBudget,canonical_ledger,ledger_lock
from stbench.codex_baseline import ResponsesGateway,CodexProvider
from stbench.transport import MeteredProvider
from stbench.providers.base import ProviderError
from stbench.harness.engine import Solver,solve_problem
from stbench.harness.prompts import build_system_prompt
from stbench.platforms import CodesysBackend
from stbench.evaluation import atomic_json
from campaign_status import load,registered_process_alive
from resume_user_paused_campaign import current_process_marker

CONCISE='返回一个最简完整 FUNCTION_BLOCK FB，不附讲解、测试程序、备选实现或大段注释。先确保接口、声明和所有控制块闭合；只使用 IEC 基本语法。'


def scoped_budget(cfg,plan):
    if plan.get('incremental_cap_cny')!=10 or plan.get('total_authorized_cny')!=75:
        raise RuntimeError('Diagnostic authorization must retain 10 CNY additional / 75 CNY total')
    ceiling=plan['baseline_spent_cny']+10
    if plan.get('cumulative_ceiling_cny')!=ceiling:
        raise RuntimeError('Diagnostic cumulative ceiling changed')
    budget=CampaignBudget(canonical_ledger(cfg),'final',phase_caps=cfg['phase_limits'])
    budget.ceiling_override=min(ceiling,65)
    return budget


def response_capture(path):
    def capture(data,protocol):
        message=(data.get('choices') or [{}])[0].get('message',{}) if protocol=='chat' else {}
        safe=dict(model=data.get('model'),usage=data.get('usage'),protocol=protocol,
                  finish_reason=(data.get('choices') or [{}])[0].get('finish_reason'),
                  message={k:message[k] for k in ('content','reasoning_content','reasoning_details') if k in message})
        text=json.dumps(safe,ensure_ascii=False)
        text=re.sub(r'\bsk-[A-Za-z0-9_-]{16,}','[redacted]',text)
        atomic_json(path,json.loads(text))
    return capture


def status(cfg):
    root=Path(cfg['campaign_root']);state=load(root/'diagnostic_state.json');plan=load(root/'diagnostic_plan.json')
    ledger=load(cfg['budget_ledger_path']);records=[p for p in (root/'jobs').glob('*/*.json') if not p.name.endswith('.response.json')]
    alive=registered_process_alive(load(root/'active_run.json'))
    lines=[{'running':'小规模诊断正在运行','completed':'小规模诊断已结束','stopped':'小规模诊断已停止，需要检查'}.get(state.get('state'),'诊断准备中'),'',
           '更新时间：'+datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S'),
           f'已保存诊断题次：{len(records)}/24（六题 × 两框架 × 两提示）',
           f"本轮累计计入增量：{max(0,ledger.get('spent_cny',0)-plan.get('baseline_spent_cny',0)):.4f}/10 元（含在途及历史预留口径）",
           f"共享账本累计：{ledger.get('spent_cny',0):.4f}/75 元",'',
           '这些是 MiniMax 小样本诊断，不能替代新的四组全量实验。']
    if alive:lines.append('电脑需保持开机联网，避免合盖、睡眠或关机。')
    if state.get('error'):lines.append('停止原因：'+state['error'])
    if state.get('state')=='completed':lines.append('结果见 diagnostic_summary.json；未自动启动全量 R9。')
    text='\n'.join(lines)+'\n';(root/'诊断状态.txt').write_text(text,encoding='utf-8')
    (root/'诊断状态.html').write_text('<meta charset="utf-8"><meta http-equiv="refresh" content="15"><style>body{font:18px/1.8 system-ui;margin:40px}pre{white-space:pre-wrap}</style><pre>'+html.escape(text)+'</pre>',encoding='utf-8')
    return alive,state.get('state') in ('completed','stopped')


def summarize(cfg,plan):
    root=Path(cfg['campaign_root']);rows=[]
    for fw in ('custom','codex'):
        for variant in ('baseline','concise'):
            records=[load(p) for p in (root/'jobs'/(fw+'_'+variant)).glob('*.json') if not p.name.endswith('.response.json')]
            rows.append(dict(framework=fw,variant=variant,n=6,attempted=sum(bool(r.get('attempts')) for r in records),
                generated=sum(any(a.get('code') for a in r.get('attempts',[])) for r in records),solved=sum(bool(r.get('solved')) for r in records),
                incomplete=sum(a.get('provider_error','').startswith('Generation incomplete/empty:') for r in records for a in r.get('attempts',[]))))
    atomic_json(root/'diagnostic_summary.json',dict(rows=rows,source_sha256=digest(),
        baseline_spent_cny=plan['baseline_spent_cny'],additional_accounted_cny=load(cfg['budget_ledger_path'])['spent_cny']-plan['baseline_spent_cny'],
        automatic_full_run=False,notice='Single-candidate MiniMax prompt diagnosis; not a four-condition formal benchmark'))


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--prepare',action='store_true');ap.add_argument('--watch',action='store_true')
    ap.add_argument('--live',action='store_true');ap.add_argument('--validation',type=Path);args=ap.parse_args()
    cfg=configuration(str(ROOT/'config.r9_diagnostic.json'));root=Path(cfg['campaign_root']);origin=load(ROOT/'ORIGIN_R8.json')
    if args.watch:
        while True:
            alive,terminal=status(cfg)
            if terminal:return 0
            if not alive and load(root/'active_run.json'):
                atomic_json(root/'diagnostic_state.json',dict(state='stopped',error='Registered diagnostic runner disappeared; inspect reservations before restarting'))
                status(cfg);return 2
            time.sleep(15)
    if not args.validation:raise RuntimeError('Current validation is required')
    limits=cfg['limits']
    if tuple(limits.get(k) for k in ('task_seconds','request_seconds','max_candidates','mc_seconds','max_output_tokens'))!=(1200,420,1,30,16384):
        raise RuntimeError('Controlled diagnostic limits changed')
    proof=load(args.validation)
    if proof.get('passed') is not True or proof.get('source_sha256')!=digest():raise RuntimeError('Current source validation mismatch')
    jobs=[dict(pid=pid,framework=fw,variant=variant) for i,pid in enumerate(PILOT)
          for fw,variant in ([('custom','baseline'),('codex','baseline'),('custom','concise'),('codex','concise')][i%4:]+
                            [('custom','baseline'),('codex','baseline'),('custom','concise'),('codex','concise')][:i%4])]
    selected={p.pid:p for _,p,_ in tasks()};spec=cfg['models'][1]
    first_pool=sum(first_candidate_bound(spec,selected[j['pid']],cfg,j['framework']) for j in jobs)
    if first_pool>10:raise RuntimeError('Worst-case first-request reservations exceed this diagnostic allocation')
    plan=dict(source_sha256=digest(),incremental_cap_cny=10,total_authorized_cny=75,
              config_sha256=hashlib.sha256(json.dumps(cfg,sort_keys=True).encode()).hexdigest(),
              runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              baseline_spent_cny=origin['budget_baseline_cny'],baseline_event_count=origin['baseline_event_count'],
              cumulative_ceiling_cny=origin['diagnostic_cumulative_ceiling_cny'],jobs=jobs,
              protocol='chat',output_cap=16384,max_candidates=1,task_seconds=1200,request_seconds=420,
              mc_seconds=30,verification_after_tests=True,
              validation=str(args.validation.resolve()),comparison='prompt only; common tests-first judgement')
    plan['first_request_upper_bound_cny']=first_pool
    planfile=root/'diagnostic_plan.json'
    if args.prepare:
        if planfile.exists():
            if (root/'active_run.json').exists() or (root/'diagnostic_state.json').exists():
                raise RuntimeError('A diagnostic has started; prepare cannot change it')
            old=load(planfile)
            if old==plan:print('Already prepared; no model request sent',flush=True);return 0
            history=root/'preparation_history'/old['source_sha256']
            history.mkdir(parents=True,exist_ok=False)
            for name in ('diagnostic_plan.json','prepared.json','native_preflight.json'):
                if (root/name).exists():shutil.copy2(root/name,history/name)
        atomic_json(planfile,plan);native_preflight(cfg,root)
        atomic_json(root/'prepared.json',dict(source_sha256=digest(),native_controls='passed',generation_requests=0))
        print('Prepared 24 diagnostic jobs; native controls passed; no model request sent',flush=True);return 0
    if not args.live:raise RuntimeError('Explicit live diagnostic action required')
    if load(planfile)!=plan or load(root/'prepared.json').get('source_sha256')!=digest():raise RuntimeError('Prepared plan changed')
    marker=load(root/'active_run.json')
    if marker or load(root/'diagnostic_state.json'):raise RuntimeError('Diagnostic run already started; no automatic resume')
    catalog=credential_check(cfg);atomic_json(root/'credential_check.json',catalog)
    if not all(catalog['selected_models'].values()):raise RuntimeError('Selected models absent from catalog')
    import zipfile
    with zipfile.ZipFile(root/'frozen_source_before_diagnostics.zip','x',zipfile.ZIP_DEFLATED) as archive:
        for folder in ('stbench','scripts','datasets'):
            for path in sorted((ROOT/folder).rglob('*')):
                if path.is_file() and '__pycache__' not in path.parts:archive.write(path,path.relative_to(ROOT).as_posix())
        archive.write(ROOT/'config.r9_diagnostic.json','config.r9_diagnostic.json')
    budget=scoped_budget(cfg,plan)
    with ledger_lock(canonical_ledger(cfg)):
        initial=budget.read()
        if initial['spent_cny']!=plan['baseline_spent_cny'] or len(initial['events'])!=plan['baseline_event_count']:
            raise RuntimeError('Shared ledger changed before diagnostic start; review the fixed plan')
        atomic_json(root/'active_run.json',dict(**current_process_marker(),state='running',source_sha256=digest(),entry='r9_diagnostics.py'))
    awake=bool(ctypes.windll.kernel32.SetThreadExecutionState(0x80000001))
    atomic_json(root/'diagnostic_state.json',dict(state='running',source_sha256=digest(),system_awake_requested=awake))
    try:
        for job in jobs:
            budget.snapshot();status(cfg);p=selected[job['pid']];folder=root/'jobs'/(job['framework']+'_'+job['variant'])
            folder.mkdir(parents=True,exist_ok=True)
            with ExitStack() as stack:
                transport=MeteredProvider(spec,budget,max_tokens=16384,protocol='chat',timeout=420)
                transport.response_observer=response_capture(folder/(p.pid+'.response.json'))
                sent=[0]
                def one_request(messages):
                    if sent[0]:raise ProviderError('Diagnostic single-request limit reached; no request sent')
                    sent[0]+=1
                    public=dict(model=spec['model'],protocol='chat',max_tokens=16384,timeout_seconds=420,
                                messages=[{k:m[k] for k in ('role','content') if k in m} for m in messages])
                    safe=re.sub(r'\bsk-[A-Za-z0-9_-]{16,}','[redacted]',json.dumps(public,ensure_ascii=False,indent=2))
                    (folder/(p.pid+'.request.txt')).write_text(safe,encoding='utf-8')
                transport.before_send=one_request
                if job['framework']=='codex':
                    gateway=stack.enter_context(ResponsesGateway(provider=transport,model=spec['model']))
                    provider=CodexProvider(gateway,model=spec['model'],work_root=Path(cfg['platform_root'])/'builds/codex_r9_diagnostics',timeout=450)
                else:provider=transport
                system=build_system_prompt()+('\n'+cfg['strategy'].get('extra_instruction','') if job['framework']=='custom' else '')
                if job['variant']=='concise':system+='\n'+CONCISE
                solver=Solver(provider,max_iters=1,system_prompt=system,include_ltl=True,model_check=True,
                    verification_after_tests=True,task_seconds=1200,mc_seconds=30,request_window_seconds=450,
                    backends=(CodesysBackend(cfg),),cache_dir=root/'cache'/(job['framework']+'_'+job['variant']))
                record=solve_problem(p,solver,log_dir=folder)
                print(job['pid'],job['framework'],job['variant'],record.solved,record.stop_reason,flush=True)
            budget.snapshot()
        summarize(cfg,plan)
    except BaseException as error:
        atomic_json(root/'diagnostic_state.json',dict(state='stopped',error=str(error),source_sha256=digest(),at=datetime.now(timezone.utc).isoformat()))
        status(cfg);raise
    else:
        atomic_json(root/'diagnostic_state.json',dict(state='completed',source_sha256=digest(),at=datetime.now(timezone.utc).isoformat()))
        status(cfg)
    finally:
        if awake:ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
    return 0


if __name__=='__main__':raise SystemExit(main())

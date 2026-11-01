"""Approved two-model campaign: shared budget, protocol probing and frozen evaluation."""
from __future__ import annotations
import argparse
import contextlib
import csv
import copy
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import urllib.request
import urllib.error
from .billing import CampaignBudget,canonical_ledger,phase_limits
from .transport import MeteredProvider,HTTPFailure
from .live import validate_live_config
from .evaluation import atomic_json
from .harness.runner import Solver,solve_problem,summarize
from .harness.engine import RunRecord
from .harness.prompts import build_task_prompt,build_system_prompt
from .codex_baseline import ResponsesGateway,CodexProvider
from .platforms import CodesysBackend,OpenPLCBackend
from .portability import adapt,PROFILE
from .providers.base import ProviderError

ROOT=Path(__file__).resolve().parents[1]
PILOT=["self-easy-02","self-medium-03","self-medium-01","public-hard-04","self-hard-06","self-hard-07"]
EXPECTED_MODELS=["deepseek-v4-pro-0813","MiniMax-M2.7"]
STRATEGIES=[
    '请使用题目接口与 IEC ST 基本语法。跨拍状态放在 VAR；按钮边沿先计算，再执行状态转移，最后更新历史；输出每拍显式赋值。',
    '仅输出完整 FUNCTION_BLOCK FB 及必要 TYPE。不要使用 METHOD、ACTION、PROPERTY、指针或外部定时器。变量避免 s、r、dt、if 等保留名；位移采用 SHL/SHR 函数。数组上下界和类型转换须显式检查。',
    '逐项落实题面中的初始化、复位优先级、安全联锁、饱和边界、故障恢复和连续扫描条件。相同按钮持续为 TRUE 不能重复触发上升沿。保持正确接口并输出完整代码。'
]

def digest():
    return hashlib.sha256(b"".join(p.read_bytes() for p in sorted((ROOT/"stbench").rglob("*.py")))).hexdigest()

def credentials(cfg):
    for spec in cfg['models']:
        name=spec['api_key_env']
        if not os.environ.get(name) and os.name=='nt':
            import winreg
            try:
                with winreg.OpenKey(winreg.HKEY_CURRENT_USER,'Environment') as key:
                    os.environ[name]=winreg.QueryValueEx(key,name)[0]
            except OSError:pass
        if not os.environ.get(name):raise ProviderError("Missing credential: "+name)

def credential_check(cfg):
    credentials(cfg)
    request=urllib.request.Request('https://www.dmxapi.cn/v1/models',headers={
        'Authorization':'Bearer '+os.environ['DMXAPI_API_KEY']})
    try:
        with urllib.request.urlopen(request,timeout=30) as reply:data=json.load(reply)
    except urllib.error.HTTPError as error:
        raise ProviderError('Read-only model catalog HTTP '+str(error.code)+'; no generation request sent') from None
    except (OSError,ValueError) as error:
        raise ProviderError('Read-only model catalog '+type(error).__name__+'; no generation request sent') from None
    models={m.get('id') for m in data.get('data',[]) if isinstance(m,dict)}
    return dict(authenticated=True,selected_models={m:m in models for m in EXPECTED_MODELS},generation_requests=0)

def configuration(path):
    cfg=json.loads(Path(path or ROOT/'config.dmxapi.json').read_text(encoding='utf-8'))
    validate_live_config(cfg);canonical_ledger(cfg);phase_limits(cfg.get('phase_limits'))
    request_seconds=cfg.get('limits',{}).get('request_seconds',180)
    overhead=cfg.get('limits',{}).get('codex_overhead_seconds',30)
    if (isinstance(request_seconds,bool) or not isinstance(request_seconds,(int,float)) or
        not 0<request_seconds<=cfg['limits']['task_seconds'] or
        isinstance(overhead,bool) or not isinstance(overhead,(int,float)) or not 2<=overhead<=60):
        raise ProviderError('Invalid bounded request timeout configuration')
    if request_seconds+overhead>=cfg['limits']['task_seconds']:
        raise ProviderError('Request and CLI overhead must fit inside the task deadline')
    if [m['model'] for m in cfg['models']]!=EXPECTED_MODELS:
        raise ProviderError('Campaign model selection changed; requires a separately approved campaign')
    for m in cfg['models']:
        if m.get('generation_protocol','chat') not in ('chat','responses'):
            raise ProviderError('Generation protocol must be explicit Chat or Responses')
        if m['base_url']!='https://www.dmxapi.cn/v1' or m['api_key_env']!='DMXAPI_API_KEY':
            raise ProviderError('Campaign credential destination mismatch')
        if set(m.get('parameters',{})) & {'model','messages','input','stream','max_tokens','max_output_tokens','tools'}:
            raise ProviderError('Model parameters cannot override campaign transport/limits')
    return cfg

def tasks():
    from .cli import problems,reference
    return [(p,*adapt(p,reference(p),'codesys')[:2]) for p in problems()]

def budget_for(cfg,phase):
    return CampaignBudget(canonical_ledger(cfg),phase,phase_caps=cfg.get('phase_limits'))

def pilot_ready(cfg,rows):
    expected=set(group_order(cfg))
    return (len(rows)==len(expected) and {(r.get('framework'),r.get('model_id')) for r in rows}==expected and
            all(r.get('n')==len(PILOT) and r.get('attempted')==len(PILOT) and
                1<=r.get('generated',0)<=len(PILOT) for r in rows))

def snapshot(cfg, routes):
    from .cli import problems
    files=[p for folder in ('stbench','datasets') for p in (ROOT/folder).rglob('*')
           if p.is_file() and p.suffix in ('.py','.json','.st')]
    safe=json.loads(json.dumps(cfg));safe.pop('campaign_root',None)
    return dict(version=3,profile=PROFILE,judge_sha256=digest(),config=safe,routes=routes,
                tasks=[dict(pid=p.pid,cases=len(p.test_cases)) for p in problems()],
                files={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)})

def require_freeze(path, current):
    if path.exists():
        if json.loads(path.read_text(encoding='utf-8'))!=current:
            raise ProviderError('Frozen source/data/config changed; use a new complete experiment version')
    else:atomic_json(path,current)

def native_preflight(cfg,out):
    from .schema import Problem
    p=Problem.from_dict(dict(pid='campaign-control',source='selfmade',difficulty='easy',title='compiler control',requirements='b=a',
        variables=[dict(name='a',data_type='BOOL',direction='input'),dict(name='b',data_type='BOOL',direction='output')]))
    code='FUNCTION_BLOCK FB\nVAR_INPUT a:BOOL; END_VAR\nVAR_OUTPUT b:BOOL; END_VAR\nb:=a;\nEND_FUNCTION_BLOCK'
    rows={}
    for backend in (CodesysBackend(cfg),OpenPLCBackend(cfg)):
        positive=backend.compile(code,p);negative=backend.compile(code.replace('b:=a;','b:=;'),p)
        rows[backend.name]=dict(positive=positive.to_dict(),negative=negative.to_dict())
    atomic_json(out/'native_preflight.json',rows)
    if any(v['positive']['status']!='passed' or v['negative']['status']!='failed' for v in rows.values()):
        raise ProviderError('Native preflight failed; no model request sent')

def probe(cfg,out):
    budget=budget_for(cfg,'preflight');routes={}
    catalog=credential_check(cfg);atomic_json(out/'credential_check.json',catalog)
    if not all(catalog['selected_models'].values()):raise ProviderError('Selected model absent from authenticated catalog; no generation request sent')
    for spec in cfg['models']:
        message=[dict(role='user',content='Reply exactly OK, without explanation.')]
        path=out/(spec['id']+'_protocol.json')
        row=json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
        accepted={m.casefold() for m in spec.get('accepted_models',[spec['model']])}
        def valid(prefix):
            usage=row.get(prefix+'_usage',{})
            return (str(row.get(prefix+'_model','')).casefold() in accepted and
                    all(isinstance(usage.get(k),int) and not isinstance(usage[k],bool) and usage[k]>=0
                        for k in ('prompt_tokens','completion_tokens')))
        if row and not valid('chat'):raise ProviderError('Saved protocol probe has invalid identity/usage')
        if not row:
            chat=MeteredProvider(spec,budget,max_tokens=512)
            result=chat.generate(message)
            row=dict(chat_model=result.model,chat_usage=result.usage)
            atomic_json(path,row)
        if row.get('route')=='responses' and valid('responses'):
            routes[spec['id']]='responses';continue
        if row.get('route')=='chat' and row.get('responses_rejected_http') in (400,404,405,422):
            routes[spec['id']]='chat';continue
        native=MeteredProvider(spec,budget,max_tokens=512,protocol='responses');native.probe_rejection_allowed=True
        try:
            result=native.generate(message);route='responses'
            row.update(responses_model=result.model,responses_usage=result.usage)
        except HTTPFailure as error:
            if error.status not in (400,404,405,422):raise
            route='chat';row['responses_rejected_http']=error.status
        routes[spec['id']]=route;row['route']=route
        atomic_json(path,row)
    atomic_json(out/'routes.json',routes)
    return routes

def group_order(cfg):
    ids=[m['id'] for m in cfg['models']]
    return [('custom',ids[0]),('codex',ids[0]),('custom',ids[1]),('codex',ids[1])]

def check_output_limits(cfg,out):
    """Exercise a small total-output cap before any expensive candidate generation."""
    budget=budget_for(cfg,'preflight');rows=[]
    for spec in cfg['models']:
        protocol=spec.get('generation_protocol','chat');cap=512
        provider=MeteredProvider(spec,budget,max_tokens=cap,protocol=protocol,
            timeout=cfg['limits'].get('request_seconds',180))
        try:
            provider.generate([dict(role='user',content='Print every integer from 1 through 10000, separated by commas. Do not summarize or skip any integers.')])
        except ProviderError as error:
            if not str(error).startswith('Generation incomplete/empty:'):raise
        receipt=provider.last_receipt
        passed=(receipt.get('finish_reason') in ('length','incomplete') and
                0<receipt.get('completion_tokens',0)<=cap)
        rows.append(dict(model=spec['model'],protocol=protocol,cap=cap,passed=passed,receipt=receipt))
        result=dict(passed=all(x['passed'] for x in rows) and len(rows)==len(cfg['models']),
            source_sha256=digest(),policy_sha256=output_limit_signature(cfg),models=rows)
        atomic_json(out/'output_limit_check.json',result)
        if not passed:raise ProviderError('Total output cap was not demonstrated; no candidate batch started')
    return result

def output_limit_signature(cfg):
    return hashlib.sha256(json.dumps(dict(models=cfg['models'],
        max_output_tokens=cfg['limits']['max_output_tokens']),sort_keys=True).encode()).hexdigest()

def limits_verified(cfg,out):
    path=out/'output_limit_check.json'
    result=json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
    return (result.get('passed') is True and result.get('source_sha256')==digest() and
            result.get('policy_sha256')==output_limit_signature(cfg))

def first_candidate_bound(spec,p,cfg,framework):
    messages=[dict(role='system',content=build_system_prompt()),dict(role='user',content=build_task_prompt(p))]
    # Extra headroom for Codex CLI's documented developer message overhead.
    overhead=45056 if framework=='codex' else 8192
    return ((len(json.dumps(messages,ensure_ascii=False).encode())+overhead)*spec['input_cny_per_million']+
             cfg['limits']['max_output_tokens']*spec['output_cny_per_million'])/1e6

def run_stage(cfg,out,stage,routes,*,round_number=1,offline=False,only_job=None,repair_pass=False):
    from .providers.mock import MockProvider
    selected=tasks()
    if stage in ('pilot','develop','retest'):selected=[t for t in selected if t[0].pid in PILOT]
    phase={'pilot':'preflight','develop':'development','final':'final','retest':'retest'}[stage]
    budget=budget_for(cfg,phase) if not offline else None
    stage_out=out/(stage if stage!='develop' else 'develop_round_'+str(round_number));stage_out.mkdir(parents=True,exist_ok=True)
    current=snapshot(cfg,routes)
    require_freeze(stage_out/'freeze.json',current)
    if stage=='final' and len(selected)!=35:raise ProviderError('Final experiment must contain all 35 tasks')
    specs={s['id']:s for s in cfg['models']};jobs=[(t,fw,mid) for t in selected for fw,mid in group_order(cfg)
        if stage not in ('develop','retest') or fw=='custom']
    if only_job is not None:
        if stage!='pilot':raise ProviderError('Single-job checks are limited to the pilot stage')
        jobs=[job for job in jobs if (job[1],job[2],job[0][1].pid)==only_job]
        if not jobs:raise ProviderError('Unknown pilot job')
    if budget and stage=='develop':
        formal_pool=sum(first_candidate_bound(specs[mid],p,cfg,fw) for _,p,_ in tasks() for fw,mid in group_order(cfg))
        budget.ceiling_override=max(0.,65-formal_pool)
    remaining={}
    for (_,p,_),framework,mid in jobs:
        file=stage_out/(framework+'_'+mid)/(p.pid+'.json')
        prior=RunRecord.load(file) if file.exists() else None
        if not prior or not prior.attempts:remaining[(p.pid,framework,mid)]=first_candidate_bound(specs[mid],p,cfg,framework)
    if budget and stage=='final' and sum(remaining.values())>budget.remaining():
        raise ProviderError('Remaining first-candidate worst-case reservations exceed stage budget; no partial final run started')
    for (original,p,source),framework,mid in jobs:
        folder=stage_out/(framework+'_'+mid);file=folder/(p.pid+'.json')
        prior=RunRecord.load(file) if file.exists() else None
        if prior and (len(prior.attempts)>=prior.max_iters or prior.stop_reason not in ('provider_error','budget_exhausted','repair_budget_deferred','')):
            continue
        job_started=time.monotonic()
        timing_file=folder/(p.pid+'.timing.json')
        previous_timing=json.loads(timing_file.read_text(encoding='utf-8')) if timing_file.exists() else {}
        record=None;report_on_exit=False
        def finish_timing():
            elapsed=time.monotonic()-job_started
            segments=previous_timing.get('active_wall_segments',[])
            if not segments and previous_timing.get('active_wall_seconds'):
                segments=[previous_timing['active_wall_seconds']]
            segments=segments+[elapsed]
            saved=record or (RunRecord.load(file) if file.exists() else None)
            atomic_json(timing_file,dict(active_wall_seconds=sum(segments),active_wall_segments=segments,
                model_and_judge_seconds=saved.total_latency_s if saved else 0))
            if report_on_exit:report(cfg,stage_out,task_ids=[t[1].pid for t in selected])
        with contextlib.ExitStack() as stack:
            # Registered first, so CLI/gateway cleanup finishes before the final clock snapshot.
            stack.callback(finish_timing)
            if offline:
                if framework=='custom':provider=MockProvider(model=specs[mid]['model'],reference=source)
                else:
                    gateway=stack.enter_context(ResponsesGateway(mock_text=source,model=specs[mid]['model']))
                    provider=CodexProvider(gateway,model=specs[mid]['model'],mock=True,work_root=Path(cfg['platform_root'])/'builds/codex')
                backends=()
            else:
                transport=MeteredProvider(specs[mid],budget,max_tokens=cfg['limits']['max_output_tokens'],
                    protocol=specs[mid].get('generation_protocol',routes[mid] if framework=='codex' else 'chat'),
                    timeout=cfg['limits'].get('request_seconds',180))
                guard_state={'first':(p.pid,framework,mid) in remaining}
                def guard(messages,key=(p.pid,framework,mid),transport=transport,state=guard_state):
                    # First request claims its protected slot; repairs must preserve every unvisited task.
                    pool=sum(v for k,v in remaining.items() if k!=key) if stage=='final' else 0.
                    budget.protected_cny=pool
                    if state['first'] and transport.upper(messages)>remaining[key]:
                        raise ProviderError('First-candidate input exceeded protected reservation; no request sent')
                    state['first']=False
                    # The transport computes the exact actual request upper bound before reserving.
                transport.before_send=guard
                if framework=='custom':provider=transport
                else:
                    gateway=stack.enter_context(ResponsesGateway(provider=transport,model=specs[mid]['model']))
                    provider=CodexProvider(gateway,model=specs[mid]['model'],work_root=Path(cfg['platform_root'])/'builds/codex',
                        timeout=min(cfg['limits']['task_seconds'],cfg['limits'].get('request_seconds',180)+
                                    cfg['limits'].get('codex_overhead_seconds',30)))
                backends=(CodesysBackend(cfg),)
            limits=cfg['limits']
            system=build_system_prompt()+('\n'+cfg.get('strategy',{}).get('extra_instruction','') if framework=='custom' else '')
            solver=Solver(provider,max_iters=1 if stage=='pilot' else limits['max_candidates'],system_prompt=system,
                include_ltl=cfg.get('strategy',{}).get('include_ltl',True) if framework=='custom' else True,
                model_check=not offline,task_seconds=limits['task_seconds'],mc_seconds=limits['mc_seconds'],backends=backends,
                defer_budget_repairs=stage=='final',
                # Use the same full request/CLI window for both experimental frameworks.
                request_window_seconds=0 if offline else limits.get('request_seconds',180)+limits.get('codex_overhead_seconds',30),
                cache_dir=Path(cfg['platform_root'])/'cache/campaign_judges'/hashlib.sha256(str(folder.resolve()).encode()).hexdigest())
            record=solve_problem(p,solver,log_dir=folder,resume=file.exists(),
                active_elapsed_before=previous_timing.get('active_wall_seconds',0.))
            if record.attempts:remaining.pop((p.pid,framework,mid),None)
            if record.best and record.best.code and not offline:
                checkfile=folder/(p.pid+'.openplc.json')
                native=OpenPLCBackend(cfg)
                prior=json.loads(checkfile.read_text(encoding='utf-8')) if checkfile.exists() else {}
                if prior.get('candidate_hash')!=record.best.code_hash or prior.get('platform_identity')!=native.identity():
                    left=limits['task_seconds']-max(record.total_latency_s,
                        previous_timing.get('active_wall_seconds',0.)+time.monotonic()-job_started)
                    if left<=0:
                        check=dict(status='timeout',platform='openplc',platform_identity=native.identity(),
                                   diagnostics=['Task deadline reached before OpenPLC review'])
                    else:
                        native.timeout=min(native.timeout,left)
                        check=native.compile(record.best.code,p).to_dict()
                    atomic_json(checkfile,dict(candidate_hash=record.best.code_hash,**check))
            print(stage,framework,mid,p.pid,record.solved,record.stop_reason,flush=True)
            if budget:
                try:
                    budget.snapshot() # A malformed/unknown charge halts the entire batch.
                    if 'Budget coverage guard' in record.error:
                        if record.stop_reason!='repair_budget_deferred':raise ProviderError(record.error)
                        if repair_pass:break
                except ProviderError:
                    report_on_exit=True
                    raise
    report(cfg,stage_out,task_ids=[p.pid for _,p,_ in selected])
    if stage=='final' and not repair_pass:
        deferred=any(RunRecord.load(f).stop_reason=='repair_budget_deferred'
            for f in stage_out.glob('*/*.json') if not f.name.endswith(('.timing.json','.openplc.json')))
        if deferred:
            # First requests are now covered. Revisit deferred repairs with the remaining budget.
            run_stage(cfg,out,stage,routes,round_number=round_number,offline=offline,repair_pass=True)
    if stage=='develop':
        history_file=out/'optimization.json'
        history=json.loads(history_file.read_text(encoding='utf-8')) if history_file.exists() else []
        results=json.loads((stage_out/'summary.json').read_text(encoding='utf-8'))
        score=sum(r['solve_rate'] for r in results if r['framework']=='custom')
        history=[r for r in history if r['round']!=round_number]
        previous=max((r['score'] for r in history),default=-1)
        history.append(dict(round=round_number,score=score,improved=score>previous,freeze_sha256=hashlib.sha256(json.dumps(current,sort_keys=True).encode()).hexdigest()))
        atomic_json(history_file,history)

def report(cfg,folder,*,task_ids=None):
    from .cli import problems,export_summary
    ps=[p for p in problems() if task_ids is None or p.pid in task_ids];rows=[]
    specs={s['id']:s for s in cfg['models']}
    for framework,mid in group_order(cfg):
        records=[];reviewed=0;openplc_pass=0;active_seconds=0
        for p in ps:
            f=folder/(framework+'_'+mid)/(p.pid+'.json')
            if f.exists():records.append(RunRecord.load(f))
            else:records.append(RunRecord(p.pid,specs[mid]['model'],framework,'iterative',5,tests_total=len(p.test_cases),stop_reason='not_run'))
            native=f.with_name(p.pid+'.openplc.json')
            if native.exists():
                checked=json.loads(native.read_text(encoding='utf-8'));reviewed+=1
                openplc_pass+=checked['status']=='passed'
            timing=f.with_name(p.pid+'.timing.json')
            if timing.exists():active_seconds+=json.loads(timing.read_text(encoding='utf-8'))['active_wall_seconds']
        row=summarize(records)|dict(framework=framework,model_id=mid,attempted=sum(bool(r.attempts) for r in records),
            generated=sum(any(a.code for a in r.attempts) for r in records),group_active_wall_seconds=active_seconds,
            openplc_checked=reviewed,openplc_passed=openplc_pass,cost_basis='Upper public-price estimate; compare upstream bill',
            failure_classes={reason:sum(r.stop_reason==reason for r in records) for reason in sorted({r.stop_reason for r in records})})
        rows.append(row)
    export_summary(folder/'summary.json',rows)
    title='# 代表题试跑结果（含未运行项）' if folder.name=='pilot' else '# 四组实验结果'
    text=[title,'', '表中费用仅为已返回用量的公开价估计；共享账本另保留未确认费用。功能测试为解释器执行，平台为真实编译。', '',
          '|框架|模型|已尝试/题数|CODESYS 首次/最终|用例|整题|OpenPLC|token|已返回费用估计|',
          '|---|---|---:|---|---|---|---|---:|---:|']
    for r in rows:
        c=r.get('native_compilation',{}).get('codesys',{})
        text.append(f"|{r['framework']}|{r['model']}|{r['attempted']}/{r['n']}|{c.get('first_compile_rate',0):.1%}/{c.get('final_compile_rate',0):.1%}|{r['tests_passed']}/{r['tests_total']}|{r['solve_rate']:.1%}|{r['openplc_passed']}/{r['n']}|{r['total_tokens']}|{r['total_cost_cny']:.4f}|")
    text+=['','## 验证状态','']+[f"- {r['framework']}/{r['model_id']}：{r['verification_statuses']}" for r in rows]
    ledger=canonical_ledger(cfg)
    if ledger.exists():
        state=json.loads(ledger.read_text(encoding='utf-8'))
        unknown=sum(e['reserved_cny'] for e in state['events'] if e['status']=='reserved')
        text+=['','## 共享预算（报告生成时点）','',
               f"累计计入 {state['spent_cny']:.6f} 元，其中未确认预留 {unknown:.6f} 元；不是上游实际账单。",
               '账本状态：'+(state.get('halted') or '可继续；仍受阶段上限保护')]
    (folder/'results.md').write_text('\n'.join(text)+'\n',encoding='utf-8')
    bars=[]
    for i,r in enumerate(rows):
        w=400*r['solve_rate'];y=40+i*65
        bars.append(f'<text x="10" y="{y}" font-size="13">{r["framework"]}/{r["model_id"]}</text><rect x="230" y="{y-15}" width="{w}" height="22" fill="#3768a8"/><text x="650" y="{y}" font-size="13">{r["solve_rate"]:.1%}</text>')
    (folder/'solve_rates.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="730" height="300">'+''.join(bars)+'</svg>',encoding='utf-8')
    return rows

def execute_all(cfg,out):
    """Deterministic staged execution; any unconfirmed upstream result stops the process."""
    native_preflight(cfg,out)
    routes=probe(cfg,out) if not (out/'routes.json').exists() else json.loads((out/'routes.json').read_text(encoding='utf-8'))
    if not limits_verified(cfg,out):check_output_limits(cfg,out)
    run_stage(cfg,out,'pilot',routes)
    pilot=json.loads((out/'pilot/summary.json').read_text(encoding='utf-8'))
    if not pilot_ready(cfg,pilot):raise ProviderError('Pilot requires all representative requests and at least one complete candidate per condition')
    best_cfg=copy.deepcopy(cfg);best_score=(-1,-1);no_gain=0
    for round_number,hint in enumerate(STRATEGIES,1):
        candidate=copy.deepcopy(cfg);candidate['strategy']['extra_instruction']=hint
        try:run_stage(candidate,out,'develop',routes,round_number=round_number)
        except ProviderError as error:
            if 'Budget' not in str(error) and 'first-candidate' not in str(error):raise
            break
        rows=json.loads((out/('develop_round_'+str(round_number))/'summary.json').read_text(encoding='utf-8'))
        custom=[r for r in rows if r['framework']=='custom']
        score=(sum(r['solve_rate']*r['n'] for r in custom),sum(r['tests_passed'] for r in custom))
        if score>best_score:best_score=score;best_cfg=candidate;no_gain=0
        else:no_gain+=1
        if score[0]>=12 or no_gain>=3:break
    atomic_json(out/'selected_configuration.json',best_cfg)
    run_stage(best_cfg,out,'final',routes)
    rows=json.loads((out/'final/summary.json').read_text(encoding='utf-8'))
    if all(r['generated']==35 for r in rows):
        ablation=copy.deepcopy(best_cfg);ablation['strategy']['include_ltl']=False
        try:run_stage(ablation,out,'retest',routes)
        except ProviderError as error:
            if 'Budget' not in str(error) and 'first-candidate' not in str(error):raise
    atomic_json(out/'campaign_completion.json',dict(final_conditions=len(rows),
        full_generation_coverage=all(r['generated']==35 for r in rows),
        custom_goal_reached=all(r['solve_rate']==1 for r in rows if r['framework']=='custom'),
        budget=json.loads(canonical_ledger(cfg).read_text(encoding='utf-8'))))

def main(argv=None):
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('stage',choices=['prepare','credential-check','recover-identity','recover-timeout','recover-codex-timeout','recover-output-limit','limit-check','probe','pilot','develop','final','retest','report','offline-check','all'])
    ap.add_argument('--evidence',default='')
    ap.add_argument('--validation',default='')
    ap.add_argument('--only-job',nargs=3,metavar=('FRAMEWORK','MODEL_ID','PID'))
    ap.add_argument('--config',default='');ap.add_argument('--round',type=int,default=1);ap.add_argument('--live',action='store_true')
    ap.add_argument('--out',default='');args=ap.parse_args(argv)
    cfg=configuration(args.config)
    if args.stage=='recover-codex-timeout':
        if not args.evidence or not args.validation:raise ProviderError('CLI recovery requires failure and offline validation evidence')
        if cfg['limits'].get('request_seconds')!=420 or cfg['limits'].get('codex_overhead_seconds')!=30:
            raise ProviderError('CLI recovery must preserve the validated 420+30 second limits')
        failure=json.loads(Path(args.evidence).read_text(encoding='utf-8'))
        if failure.get('model') not in EXPECTED_MODELS:raise ProviderError('Unapproved CLI recovery model')
        result=budget_for(cfg,'preflight').recover_codex_timeout(args.evidence,args.validation)
        print(json.dumps(result,ensure_ascii=False));return 0
    if args.stage=='recover-output-limit':
        if not args.validation:raise ProviderError('Output-limit recovery requires offline validation')
        state=json.loads(canonical_ledger(cfg).read_text(encoding='utf-8'))
        model=state.get('events',[{}])[-1].get('request',{}).get('model')
        spec=next((s for s in cfg['models'] if s['model']==model),None)
        if not spec or spec.get('generation_protocol')!='responses':raise ProviderError('The affected model needs a native Responses policy')
        result=budget_for(cfg,'preflight').recover_output_limit(args.validation,model)
        print(json.dumps(result,ensure_ascii=False));return 0
    if args.stage=='recover-timeout':
        if not args.evidence or not args.validation:raise ProviderError('Timeout recovery requires failure and offline validation evidence')
        failure=json.loads(Path(args.evidence).read_text(encoding='utf-8'))
        if failure.get('model') not in EXPECTED_MODELS:raise ProviderError('Unapproved timeout recovery model')
        result=budget_for(cfg,'preflight').recover_timeout(args.evidence,
            request_seconds=cfg['limits'].get('request_seconds',180),validation_path=args.validation)
        print(json.dumps(result,ensure_ascii=False));return 0
    if args.stage=='recover-identity':
        if not args.evidence:raise ProviderError('Identity recovery requires --evidence')
        evidence=json.loads(Path(args.evidence).read_text(encoding='utf-8'))
        expected=evidence.get('requested_model')
        if expected not in EXPECTED_MODELS:raise ProviderError('Unapproved recovery model')
        result=budget_for(cfg,'preflight').recover_identity(args.evidence,expected)
        print(json.dumps(result,ensure_ascii=False));return 0
    if args.stage=='credential-check':print(json.dumps(credential_check(cfg),ensure_ascii=False));return 0
    out=Path(args.out or cfg['campaign_root']);out.mkdir(parents=True,exist_ok=True)
    if args.stage=='prepare':
        native_preflight(cfg,out);print('Real compiler controls passed; no model requests');return 0
    if args.stage=='report':report(cfg,out/'final');return 0
    if args.stage=='offline-check':
        run_stage(cfg,out,'pilot',{m['id']:'chat' for m in cfg['models']},offline=True);return 0
    if not args.live:raise ProviderError('Paid stage requires explicit --live; no request sent')
    if args.stage=='all':execute_all(cfg,out);return 0
    native_file=out/'native_preflight.json'
    if not native_file.exists():raise ProviderError('Run campaign prepare before paid requests')
    native=json.loads(native_file.read_text(encoding='utf-8'))
    for b in (CodesysBackend(cfg),OpenPLCBackend(cfg)):
        row=native.get(b.name,{})
        if row.get('positive',{}).get('status')!='passed' or row.get('negative',{}).get('status')!='failed' or \
           row['positive'].get('platform_identity')!=b.identity():
            raise ProviderError('Compiler controls are missing/stale; no paid request sent')
    credentials(cfg)
    if args.stage=='probe':probe(cfg,out);return 0
    if args.stage=='limit-check':check_output_limits(cfg,out);return 0
    routefile=out/'routes.json'
    if not routefile.exists():raise ProviderError('Run the paid protocol probe before this stage')
    routes=json.loads(routefile.read_text(encoding='utf-8'))
    if not limits_verified(cfg,out):
        raise ProviderError('Run the bounded output limit-check for this source before candidate generation')
    if args.stage=='final':
        pilot=out/'pilot/summary.json'
        if not pilot.exists() or not pilot_ready(cfg,json.loads(pilot.read_text(encoding='utf-8'))):
            raise ProviderError('All four pilot conditions must execute before final evaluation')
    if args.stage=='develop':
        if not 1<=args.round<=3:raise ProviderError('Development is limited to three documented rounds')
    run_stage(cfg,out,args.stage,routes,round_number=args.round,
              only_job=tuple(args.only_job) if args.only_job else None)
    return 0

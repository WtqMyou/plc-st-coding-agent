"""Twelve fresh, single-candidate jobs over the reviewed r8 contracts."""
import argparse
from contextlib import ExitStack
import copy
import ctypes
from datetime import datetime,timezone,timedelta
import hashlib
from html import escape
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO/'progress/v13_r8'))
import r8_revision as v
import r8_judge as judge
sys.path.insert(0,str(v.ENGINE/'scripts'))
import r9_four_group_readiness as support
from stbench.billing import CampaignBudget,canonical_ledger,ledger_lock,money
from stbench.campaign import configuration,credential_check,first_candidate_bound,native_preflight
from stbench.codex_baseline import CodexProvider,ResponsesGateway
from stbench.transport import MeteredProvider
from stbench.providers.base import ProviderError,ProviderResponse,extract_code
from stbench.harness.prompts import build_task_prompt
from stbench.harness.engine import RunRecord,Attempt
from stbench.st.frontend import compile_st
from stbench.evaluation import atomic_json,verification_status

CONFIG=REPO/'progress/review_r8_first_candidate/config.json'
MIRROR=REPO/'progress/evidence/review_r8_first_candidate_20261110_v2'
PIDS=('public-easy-04','self-hard-04','self-medium-03')
CAP=5.0
BASELINE=38.409603
CEILING=43.409603


def load(p):return json.loads(Path(p).read_text('utf-8')) if Path(p).exists() else {}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def obj_sha(x):return hashlib.sha256(json.dumps(x,ensure_ascii=False,sort_keys=True).encode()).hexdigest()
def stamp():return datetime.now(timezone(timedelta(hours=8))).isoformat()
def source_files():return [Path(__file__),CONFIG,CONFIG.parent/'实验方案.md',REPO/'progress/tests/test_review_r8_first_candidate.py']


def selected():
    result={p.pid:p for p in v.problems() if p.pid in PIDS}
    for p in result.values():p.mc_max_seconds=30.
    return result


def cli_identity():
    executable=Path(shutil.which('codex'))
    version=subprocess.check_output([str(executable),'--version'],text=True,encoding='utf-8',timeout=30).strip()
    return dict(executable=str(executable),executable_sha256=sha(executable),version=version)


def verify_data():
    v.verify_parent()
    for name,expected in load(v.ROOT/'snapshot_manifest.json')['files'].items():assert sha(REPO/name)==expected,name


def jobs():
    arms=[('custom','deepseek-v4pro'),('codex','deepseek-v4pro'),('custom','minimax-m27'),('codex','minimax-m27')]
    orders=[(0,1,2,3),(3,2,1,0),(1,0,3,2)]
    return [dict(pid=pid,framework=arms[i][0],model_id=arms[i][1],condition='_'.join(arms[i]),
        job_id='_'.join(arms[i])+'/'+pid) for pid,order in zip(PIDS,orders) for i in order]


def messages_for(cfg,job,p):
    task=build_task_prompt(p,include_ltl=True)
    task+='\n实现检查清单：接口匹配；复位/安全优先；状态保持；边沿先计算再更新历史；数组边界；扫描周期。'
    return [dict(role='system',content=support.system_prompt(cfg,job['framework'])),dict(role='user',content=task)]


def plan_for(cfg,state,measured=None):
    if state.get('halted'):raise RuntimeError('Ledger halted; no automatic recovery')
    expected=dict(kind='review_r8_first_candidate',additional_cap_cny=CAP,pids=list(PIDS),max_requests=12)
    if cfg['study']!=expected:raise RuntimeError('Study scope changed')
    limits=cfg['limits']
    if tuple(limits[k] for k in ('max_candidates','task_seconds','request_seconds','codex_overhead_seconds','compile_seconds','mc_seconds','max_output_tokens','verification_after_tests'))!=(1,1200,420,30,120,30,16384,True):
        raise RuntimeError('Common generation/evaluation limits changed')
    if cfg['models']!=load(REPO/'progress/r4_check_order/config.json')['models']:raise RuntimeError('Existing model selection or parameters changed')
    if money(state['spent_cny'])!=money(BASELINE):raise RuntimeError('Budget baseline changed; do not reset ledger')
    work=jobs();data=selected();specs={s['id']:s for s in cfg['models']}
    for job in work:
        model=specs[job['model_id']]
        bound=money(first_candidate_bound(model,data[job['pid']],cfg,job['framework']))
        if measured is not None:
            row=next(r for r in measured if r['job_id']==job['job_id'])
            measured_bound=money(((row['upstream_message_bytes']+4096+2048)*model['input_cny_per_million']+16384*model['output_cny_per_million'])/1e6)
            bound=max(bound,measured_bound)
        job['first_upper_cny']=float(bound)
        job['task_prompt_sha256']=obj_sha(messages_for(cfg,job,data[job['pid']]))
    upper=sum((money(j['first_upper_cny']) for j in work),money(0))
    if upper>money(CAP) or money(BASELINE)+upper>money(CEILING):raise RuntimeError('All twelve calls must fit the 5 CNY cap')
    return dict(kind='review_r8_first_candidate',planned=12,maximum_new_requests=12,task_seconds=1200,request_seconds=420,
        max_output_tokens=16384,study_additional_cap_cny=CAP,cumulative_ceiling_cny=CEILING,original_diagnostic_ceiling_cny=44.011998,
        initial_spent_cny=state['spent_cny'],initial_event_count=len(state['events']),worst_reservation_cny=float(upper),
        r8_snapshot_sha256=sha(v.ROOT/'snapshot_manifest.json'),files={p.relative_to(REPO).as_posix():sha(p) for p in source_files()},
        jobs=work,full_r9_started=False)


def budget_for(cfg,plan):
    if (plan['study_additional_cap_cny'],plan['cumulative_ceiling_cny'],plan['original_diagnostic_ceiling_cny'],plan['initial_spent_cny'])!=(CAP,CEILING,44.011998,BASELINE):
        raise RuntimeError('Budget cap changed')
    b=CampaignBudget(canonical_ledger(cfg),'final',phase_caps=cfg['phase_limits']);b.ceiling_override=CEILING
    return b


def capture(transport,budget,job,pending,folder):
    count=[0]
    def before(messages):
        if count[0]:raise ProviderError('Study request guard: only one upstream request per job')
        if money(transport.upper(messages))>money(job['first_upper_cny']):raise ProviderError('Study input guard: frozen bound exceeded; no request sent')
        budget.protected_cny=float(sum((money(x) for key,x in pending.items() if key!=job['job_id']),money(0)))
        path=folder/(job['pid']+'.request_01.json')
        if path.exists():raise ProviderError('Existing request trace; no duplicate or implicit resume')
        count[0]+=1
        atomic_json(path,json.loads(support.sanitize(json.dumps(dict(model=transport.model,protocol=transport.protocol,
            max_tokens=16384,timeout_seconds=420,messages=messages),ensure_ascii=False))))
    def response(data,protocol):
        choice=(data.get('choices') or [{}])[0];message=choice.get('message') or {}
        if protocol=='responses':message=dict(content=''.join(c.get('text','') for x in data.get('output',[]) if x.get('type')=='message' for c in x.get('content',[]) if c.get('type')=='output_text'))
        safe=dict(model=data.get('model'),protocol=protocol,usage=data.get('usage'),
            finish_reason=data.get('status') if protocol=='responses' else choice.get('finish_reason'),
            message={k:message[k] for k in ('content','reasoning_content','reasoning_details') if k in message})
        atomic_json(folder/(job['pid']+'.response_01.json'),json.loads(support.sanitize(json.dumps(safe,ensure_ascii=False))))
    transport.before_send=before;transport.response_observer=response
    return count


class Fixture:
    name='mock'
    def __init__(self,model,text):self.model=model;self.text=text;self.timeout=420;self.messages=[];self.last_charge=0.;self.last_receipt={}
    def generate(self,messages):
        if self.messages:raise ProviderError('Fixture observed a second request')
        self.messages=copy.deepcopy(messages)
        result=ProviderResponse(text=self.text,model=self.model,usage=dict(prompt_tokens=0,completion_tokens=0));result.cost_cny=0.
        return result


def offline_routes(cfg):
    rows=[];data=selected();models={m['id']:m for m in cfg['models']}
    for job in jobs():
        p=data[job['pid']];source=v.reference(p);fixture=Fixture(models[job['model_id']]['model'],source)
        messages=messages_for(cfg,job,p)
        with ExitStack() as stack:
            provider=fixture
            if job['framework']=='codex':
                gateway=stack.enter_context(ResponsesGateway(provider=fixture,model=fixture.model))
                provider=CodexProvider(gateway,model=fixture.model,work_root=Path(cfg['platform_root'])/'builds/review_r8_first_offline',mock=True,timeout=60)
            result=provider.generate(messages)
        assert result.text.strip()==source.strip()
        checked=judge.local_tests(result.text,p);assert checked.compiles and checked.all_tests_passed
        rows.append(dict(job_id=job['job_id'],model=fixture.model,protocol=models[job['model_id']]['generation_protocol'],
            upstream_message_bytes=len(json.dumps(fixture.messages,ensure_ascii=False).encode()),
            actual_messages_sha256=obj_sha(fixture.messages),gateway_requests=1,external_requests=0,tests_passed=checked.tests_passed))
        print('offline route',job['job_id'],'passed',flush=True)
    return rows


def verify_frozen(root):
    verify_data();plan=load(root/'study_plan.json');prepared=load(root/'prepared.json')
    assert plan['r8_snapshot_sha256']==sha(v.ROOT/'snapshot_manifest.json')
    assert plan['files']=={p.relative_to(REPO).as_posix():sha(p) for p in source_files()}
    assert prepared['plan_sha256']==sha(root/'study_plan.json') and prepared['validation_sha256']==sha(root/'validation.json')
    assert cli_identity()==plan['cli_identity'],'CLI identity changed'


def metrics(cfg,plan):
    root=Path(cfg['campaign_root']);rows=[]
    for condition in dict.fromkeys(j['condition'] for j in plan['jobs']):
        work=[j for j in plan['jobs'] if j['condition']==condition];records=[load(root/'jobs'/condition/(j['pid']+'.json')) for j in work]
        attempts=[a for r in records for a in r.get('attempts',[])];timings=[load(root/'jobs'/condition/(j['pid']+'.timing.json')) for j in work]
        rows.append(dict(condition=condition,framework=work[0]['framework'],model_id=work[0]['model_id'],n=3,
            recorded=sum(bool(r) for r in records),generated=sum(bool(a.get('code')) for a in attempts),
            complete_code=sum(bool(r.get('complete_code')) for r in records),solved=sum(bool(r.get('solved')) for r in records),
            codesys_passed=sum(a.get('platform_results',{}).get('codesys',{}).get('status')=='passed' for a in attempts),
            tests_passed=sum(a.get('tests_passed',0) for a in attempts),tests_total=101,
            calls=sum(t.get('upstream_requests_entered',0) for t in timings),
            mc_executed=sum(bool(a.get('judge',{}).get('model_check',{}).get('executed')) for a in attempts),
            verification_statuses=dict(__import__('collections').Counter(a.get('verification_status','not_run') for a in attempts)),
            wall_seconds=round(sum(t.get('wall_seconds',0) for t in timings),3),
            tokens=sum(a.get('prompt_tokens',0)+a.get('completion_tokens',0) for a in attempts),
            incomplete=sum(a.get('provider_error','').startswith('Generation incomplete/empty:') for a in attempts)))
    ledger=load(cfg['budget_ledger_path']);before=load(root/'ledger_before_study.json')
    return dict(label='复核r8 三题四组首候选',state=load(root/'study_state.json').get('state','prepared'),rows=rows,
        recorded=sum(r['recorded'] for r in rows),planned=12,total_accounted_cny=ledger['spent_cny'],
        study_increment_cny=round(ledger['spent_cny']-plan['initial_spent_cny'],6),
        new_events=len(ledger['events'])-plan['initial_event_count'],
        all_original_events_preserved=ledger['events'][:plan['initial_event_count']]==before['events'] and ledger.get('recoveries',[])==before.get('recoveries',[]),
        halted=ledger.get('halted'),updated_at=stamp(),full_r9_started=False)


def report(cfg,plan):
    root=Path(cfg['campaign_root']);s=metrics(cfg,plan);atomic_json(root/'study_summary.json',s)
    lines=['# 复核r8三题四组首候选','','状态：'+s['state']+f'；已归档{s["recorded"]}/12题次。',
        '每题次一个候选，不进行修复或补发。CODESYS编译与功能为主指标，形式检查单列。',
        '', '| 组别 | 已归档 | 结构完整代码 | CODESYS通过 | 功能整题 | 功能断言 | 请求 | 形式检查 |', '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for row in s['rows']:lines.append(f'| {row["condition"]} | {row["recorded"]}/3 | {row["complete_code"]}/3 | {row["codesys_passed"]}/3 | {row["solved"]}/3 | {row["tests_passed"]}/101 | {row["calls"]} | {row["mc_executed"]} |')
    lines += ['',f'本轮计入{s["study_increment_cny"]:.6f}/5.00元，累计{s["total_accounted_cny"]:.6f}/75元。阶段累计上限43.409603元。',
        '结构完整仅指解析得到完整功能块；类型、接口及逻辑仍分别检查。未运行题次保留在计划分母；形式未执行、违反、截断、未决分开记录。',
        '样本仅三题，不代表完整35题成绩或稳定框架优势。费用按配置保守计入，不代替供应商账单。']
    state=load(root/'study_state.json')
    if state.get('current_job'):lines += ['','当前题次：'+state['current_job']]
    if state.get('error'):lines += ['','停止原因：'+state['error']]
    text='\n'.join(lines)+'\n';(root/'实验状态.md').write_bytes(text.encode())
    (root/'状态.html').write_bytes(('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta http-equiv="refresh" content="15"><title>三题四组实验状态</title><style>body{font:16px/1.8 system-ui;margin:28px;color:#203047}pre{white-space:pre-wrap;overflow-wrap:anywhere}</style><h1>三题四组首候选实验</h1><pre>'+escape(text)+'</pre></html>').encode())
    MIRROR.mkdir(parents=True,exist_ok=True)
    for p in root.rglob('*'):
        if p.is_file() and (p.name in ('study_plan.json','prepared.json','validation.json','native_preflight.json','cli_offline.json','run_environment.json',
            'study_state.json','study_summary.json','实验状态.md','状态.html','completion.json','结果分析.md','analysis.json','release_manifest.json') or ('jobs' in p.relative_to(root).parts and p.suffix=='.json')):
            target=MIRROR/p.relative_to(root);target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(p.read_bytes())
    return s


def publish():
    env=dict(os.environ,GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='never')
    if subprocess.check_output(['git','branch','--show-current'],cwd=REPO,text=True).strip()!='main':raise RuntimeError('Live snapshot publishing requires main')
    if subprocess.check_output(['git','diff','--cached','--name-only'],cwd=REPO):raise RuntimeError('Other staged changes; leave them untouched')
    # Refuse publication if a credential somehow entered a supposedly public snapshot.
    for p in MIRROR.rglob('*'):
        if p.is_file():
            raw=p.read_text('utf-8');assert support.sanitize(raw)==raw,'Secret-like content in public snapshot'
    subprocess.run(['git','add','--',MIRROR.relative_to(REPO).as_posix()],cwd=REPO,check=True,capture_output=True)
    if subprocess.run(['git','diff','--cached','--quiet'],cwd=REPO).returncode:
        subprocess.run(['git','commit','-q','-m','chore: update reviewed r8 first-candidate experiment'],cwd=REPO,check=True,capture_output=True)
        subprocess.run(['git','push','origin','main'],cwd=REPO,env=env,check=True,capture_output=True,timeout=60)


def prepare(cfg):
    root=Path(cfg['campaign_root']);assert not root.exists(),'Existing run is not overwritten'
    verify_data();support.no_other_runner(cfg);before=Path(cfg['budget_ledger_path']).read_bytes();state=json.loads(before)
    plan_for(cfg,state);root.mkdir(parents=True);(root/'ledger_before_study.json').write_bytes(before)
    suites=[]
    for pattern in ('test_review_r8_first_candidate.py','test_v13_r8.py','test_v13_r7.py','test_v13_r6.py','test_v13_r5.py','test_v13_r4.py'):
        proc=subprocess.run([sys.executable,'-B','-X','utf8','-m','unittest','discover','-s','progress/tests','-p',pattern,'-q'],
            cwd=REPO,capture_output=True,text=True,encoding='utf-8',timeout=120)
        (root/(pattern+'.log')).write_bytes((proc.stdout+'\n'+proc.stderr).encode());assert proc.returncode==0,proc.stderr[-1600:]
        suites.append(dict(pattern=pattern,passed=True))
    routes=offline_routes(cfg);atomic_json(root/'cli_offline.json',dict(passed=True,routes=routes,external_requests=0))
    plan=plan_for(cfg,state,routes);plan['initial_ledger_sha256']=hashlib.sha256(before).hexdigest();plan['cli_identity']=cli_identity()
    prior_native=Path('E:/PLC_Dev/evidence/real_experiments/review_r8_first_candidate_20261110/native_preflight.json')
    reusable=load(prior_native)
    if reusable and all(reusable[b.name]['positive']['status']=='passed' and reusable[b.name]['negative']['status']=='failed'
            and reusable[b.name]['positive']['platform_identity']==b.identity() for b in (support.CodesysBackend(cfg),support.OpenPLCBackend(cfg))):
        atomic_json(root/'native_preflight.json',reusable)
        plan['native_preflight_reused']=dict(path=str(prior_native),sha256=sha(prior_native))
    else:native_preflight(cfg,root)
    assert Path(cfg['budget_ledger_path']).read_bytes()==before
    atomic_json(root/'study_plan.json',plan)
    atomic_json(root/'validation.json',dict(passed=True,suites=suites,offline_routes=12,actual_codex_cli_routes=6,
        native_controls_sha256=sha(root/'native_preflight.json'),cli_offline_sha256=sha(root/'cli_offline.json'),
        model_calls=0,ledger_unchanged=True))
    atomic_json(root/'prepared.json',dict(plan_sha256=sha(root/'study_plan.json'),validation_sha256=sha(root/'validation.json')))
    atomic_json(root/'study_state.json',dict(state='prepared',at=stamp()));report(cfg,plan)
    print('PREPARED 12 jobs; final worst reservation',plan['worst_reservation_cny'],'CNY; zero external model requests',flush=True)


def generate_job(cfg,plan,job,budget,pending,data):
    root=Path(cfg['campaign_root']);folder=root/'jobs'/job['condition'];folder.mkdir(parents=True,exist_ok=True)
    if list(folder.glob(job['pid']+'.*')):raise RuntimeError('Existing job trace; no implicit retry')
    model=next(x for x in cfg['models'] if x['id']==job['model_id']);p=data[job['pid']]
    started=time.monotonic();deadline=started+1200;record=RunRecord(p.pid,model['model'],'custom' if job['framework']=='custom' else 'codex-cli',
        job['condition'],1,experiment_kind='live',tests_total=len(p.test_cases),request_window_seconds=450)
    complete=False;fatal=None
    with ExitStack() as stack:
        transport=MeteredProvider(model,budget,max_tokens=16384,protocol=model['generation_protocol'],timeout=420)
        sent=capture(transport,budget,job,pending,folder);provider=transport
        if job['framework']=='codex':
            gateway=stack.enter_context(ResponsesGateway(provider=transport,model=transport.model))
            provider=CodexProvider(gateway,model=transport.model,work_root=Path(cfg['platform_root'])/'builds/review_r8_first_live',timeout=450)
        try:
            response=provider.generate(messages_for(cfg,job,p));source=extract_code(response.text)
            syntax=compile_st(source);complete=bool(syntax.ok and syntax.pou is not None)
            remaining=max(0,deadline-time.monotonic())
            result=judge.evaluate(source,p,model_check=True,timeout_s=remaining,task_remaining_s=remaining,
                verification_after_tests=True,backends=(support.CodesysBackend(cfg),))
            record.add(Attempt(0,source,result.compiles,result.tests_passed,len(p.test_cases),code_hash=hashlib.sha256(source.encode()).hexdigest(),
                judge=result.to_dict(),platform_results=result.platform_results,verification_status=verification_status(result),
                actual_model=response.model,prompt_tokens=response.usage['prompt_tokens'],completion_tokens=response.usage['completion_tokens'],
                latency_s=time.monotonic()-started,cost_cny=response.cost_cny))
            record.stop_reason='one_candidate_complete'
            native=result.platform_results.get('codesys',{}).get('status')
            if native in ('timeout','tool_error','unavailable') or (result.evidence_metadata.get('classification')=='tool_error' and 'timeout' not in result.mc_error.lower()):
                fatal=RuntimeError('Shared evaluation tool failure; stop instead of retrying')
        except ProviderError as exc:
            receipt=transport.last_receipt;record.error=support.sanitize(str(exc));record.stop_reason='generation_incomplete' if str(exc).startswith('Generation incomplete/empty:') else 'provider_error'
            record.add(Attempt(0,'',False,0,len(p.test_cases),provider_error=record.error,actual_model=receipt.get('model',''),
                prompt_tokens=receipt.get('prompt_tokens',0),completion_tokens=receipt.get('completion_tokens',0),
                latency_s=time.monotonic()-started,cost_cny=transport.last_charge))
            if record.stop_reason!='generation_incomplete':fatal=exc
        record.finished_at=time.time();envelope=record.to_dict();envelope.update(complete_code=complete,
            study_plan_sha256=sha(root/'study_plan.json'),r8_snapshot_sha256=plan['r8_snapshot_sha256'])
        atomic_json(folder/(p.pid+'.json'),envelope)
        atomic_json(folder/(p.pid+'.timing.json'),dict(job_id=job['job_id'],upstream_requests_entered=sent[0],
            wall_seconds=time.monotonic()-started,finished_at=stamp()))
    if fatal:raise fatal
    return envelope


def live(cfg):
    root=Path(cfg['campaign_root']);verify_frozen(root);plan=load(root/'study_plan.json')
    if load(root/'study_state.json').get('state')!='prepared' or (root/'active_run.json').exists():raise RuntimeError('Not a fresh prepared study; no automatic resume')
    if subprocess.check_output(['git','status','--porcelain'],cwd=REPO):raise RuntimeError('Commit and push preparation before generation')
    head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip()
    remote=subprocess.check_output(['git','ls-remote','origin','refs/heads/main'],cwd=REPO,text=True,env=dict(os.environ,GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='never'),timeout=30).split()[0]
    if head!=remote:raise RuntimeError('Prepared source must be pushed first')
    proof=load(root/'validation.json')
    assert proof['native_controls_sha256']==sha(root/'native_preflight.json') and proof['cli_offline_sha256']==sha(root/'cli_offline.json')
    for backend in (support.CodesysBackend(cfg),support.OpenPLCBackend(cfg)):
        assert load(root/'native_preflight.json')[backend.name]['positive']['platform_identity']==backend.identity()
    catalog=credential_check(cfg);assert all(catalog['selected_models'].values()),'Required models absent from catalog'
    budget=budget_for(cfg,plan)
    with ledger_lock(canonical_ledger(cfg)):
        support.no_other_runner(cfg)
        assert sha(canonical_ledger(cfg))==plan['initial_ledger_sha256'],'Ledger changed; no baseline reset'
        atomic_json(root/'active_run.json',dict(**support.current_process_marker(),state='running',entry='review_r8_first_candidate.py'))
    atomic_json(root/'run_environment.json',dict(published_git_commit=head,catalog=catalog,started_at=stamp(),paid_request_retries=0))
    pending={j['job_id']:j['first_upper_cny'] for j in plan['jobs']};state='stopped';awake=False
    try:
        if os.name=='nt':awake=bool(ctypes.windll.kernel32.SetThreadExecutionState(0x80000001))
        for job in plan['jobs']:
            verify_frozen(root);snapshot=budget.snapshot()
            before=load(root/'ledger_before_study.json');assert snapshot['events'][:plan['initial_event_count']]==before['events']
            assert len(snapshot['events'])-plan['initial_event_count']<=12
            atomic_json(root/'study_state.json',dict(state='running',current_job=job['job_id'],at=stamp()));report(cfg,plan)
            generate_job(cfg,plan,job,budget,pending,selected());pending.pop(job['job_id'])
            snapshot=budget.snapshot();assert snapshot['events'][-1]['status']=='settled'
            assert len(snapshot['events'])-plan['initial_event_count']<=12
            s=report(cfg,plan);assert s['all_original_events_preserved'];publish()
            print('FINISHED',job['job_id'],'records',s['recorded'],'increment',s['study_increment_cny'],flush=True)
        state='completed';atomic_json(root/'study_state.json',dict(state=state,at=stamp()))
        summary=report(cfg,plan);assert summary['recorded']==12 and summary['new_events']==12
        atomic_json(root/'completion.json',dict(completed=True,recorded=12,actual_requests=12,
            study_increment_cny=summary['study_increment_cny'],total_accounted_cny=summary['total_accounted_cny'],all_original_events_preserved=True))
    except BaseException as exc:
        atomic_json(root/'study_state.json',dict(state='stopped',error=support.sanitize(str(exc)),at=stamp()))
        raise
    finally:
        if awake:ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
        marker=load(root/'active_run.json');marker.update(state=state,ended_at=stamp());atomic_json(root/'active_run.json',marker)
        report(cfg,plan);publish()


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('command',choices=['prepare','live','sync','check'])
    cmd=parser.parse_args().command;cfg=configuration(str(CONFIG));root=Path(cfg['campaign_root'])
    if cmd=='prepare':prepare(cfg)
    elif cmd=='live':live(cfg)
    elif cmd=='sync':report(cfg,load(root/'study_plan.json'))
    else:verify_frozen(root);print('PASS frozen three-task study')

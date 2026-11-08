"""Bounded r4 verification-order pilot; immutable older campaigns remain separate."""
import argparse
from contextlib import ExitStack
import copy
import ctypes
from datetime import datetime,timedelta,timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO/'progress/v13_r4'))
import r4_revision as v
import r4_judge as judge
sys.path.insert(0,str(v.ENGINE/'scripts'))
import r9_four_group_readiness as support
from stbench.billing import CampaignBudget,canonical_ledger,ledger_lock,money
from stbench.campaign import configuration,credential_check,first_candidate_bound,native_preflight
from stbench.codex_baseline import CodexProvider,ResponsesGateway
from stbench.evaluation import atomic_json,StageResult
from stbench.harness.engine import Solver,solve_problem
from stbench.providers.base import ProviderError

CONFIG=REPO/'progress/r4_check_order/config.json'
HOME=CONFIG.parent
MIRROR=REPO/'progress/evidence/r4_check_order_20261108'
PIDS=('self-medium-03','public-hard-04')
CAP=4.50
REPAIR_BYTES=131072


def stamp():return datetime.now(timezone(timedelta(hours=8))).isoformat()
def load(path):return json.loads(Path(path).read_text('utf-8')) if Path(path).exists() else {}
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def source_files():
    return [Path(__file__),CONFIG,HOME/'实验方案.md',REPO/'progress/tests/test_r4_check_order.py']


def verify_r4():
    v.verify_parent();v.r3.r2.r1.verify_engine()
    m=load(v.ROOT/'snapshot_manifest.json')
    for name,expected in {**m['files'],**m['evidence_sha256']}.items():
        assert sha(REPO/name)==expected,name


def jobs():
    arms=[('custom',False),('codex',True),('custom',True),('codex',False)]
    result=[]
    for index,pid in enumerate(PIDS):
        for fw,after in (arms if index==0 else arms[::-1]):
            condition=fw+('_tests_first' if after else '_always_mc')
            result.append(dict(pid=pid,framework=fw,model_id='minimax-m27',condition=condition,
                job_id=condition+'/'+pid,verification_after_tests=after,task_seconds=1200))
    return result


def selected():
    result={}
    for p in v.problems():
        if p.pid not in PIDS:continue
        a=v.ROOT/'datasets'/p.source/(p.pid+'.json')
        b=REPO/'progress/v13_r2/datasets'/p.source/(p.pid+'.json')
        assert a.read_bytes()==b.read_bytes(),'The pilot tasks must not change their reviewed data contract'
        result[p.pid]=v.adapt(p)[0]
    assert set(result)==set(PIDS)
    return result


def plan_for(cfg,state):
    if state.get('halted'):raise RuntimeError('Budget halted; no automatic recovery')
    if cfg['study']!=dict(kind='r4_check_order',active_model_id='minimax-m27',additional_cap_cny=CAP,
        pids=list(PIDS),max_requests=16,conditions=['always_mc','tests_first']):
        raise RuntimeError('Pilot scope changed')
    expected=(2,1200,420,30,120,30,16384)
    if tuple(cfg['limits'][k] for k in ('max_candidates','task_seconds','request_seconds',
        'codex_overhead_seconds','compile_seconds','mc_seconds','max_output_tokens'))!=expected:
        raise RuntimeError('Common limits changed')
    if cfg['budget_cny']!=75:raise RuntimeError('Total authorization changed')
    spec=next(m for m in cfg['models'] if m['id']=='minimax-m27')
    data=selected();work=jobs()
    for job in work:
        job['first_upper_cny']=float(money(first_candidate_bound(spec,data[job['pid']],cfg,job['framework'])))
        job['repair_upper_cny']=float(money((REPAIR_BYTES*spec['input_cny_per_million']+
            16384*spec['output_cny_per_million'])/1e6))
    upper=sum((money(j['first_upper_cny'])+money(j['repair_upper_cny']) for j in work),money(0))
    ceiling=min(44.011998,float(money(state['spent_cny'])+money(CAP)))
    if money(state['spent_cny'])+upper>money(ceiling):
        raise RuntimeError('All sixteen possible calls must fit the inherited budget before starting')
    return dict(kind='r4 verification order pilot',planned=8,maximum_new_requests=16,
        task_seconds=1200,request_seconds=420,request_window_seconds=450,max_output_tokens=16384,
        study_additional_cap_cny=CAP,cumulative_ceiling_cny=ceiling,original_diagnostic_ceiling_cny=44.011998,
        original_diagnostic_baseline_cny=34.011998,total_authorized_cny=75,
        initial_spent_cny=state['spent_cny'],initial_event_count=len(state['events']),
        initial_ledger_sha256=sha(canonical_ledger(cfg)),worst_reservation_cny=float(upper),
        r4_snapshot_sha256=sha(v.ROOT/'snapshot_manifest.json'),
        files={p.relative_to(REPO).as_posix():sha(p) for p in source_files()},
        prompt_sha256={fw:hashlib.sha256(support.system_prompt(cfg,fw).encode()).hexdigest() for fw in ('custom','codex')},
        jobs=work,full_r9_started=False)


def budget_for(cfg,plan):
    if (plan['study_additional_cap_cny']!=CAP or plan['original_diagnostic_ceiling_cny']!=44.011998 or
        plan['cumulative_ceiling_cny']!=min(44.011998,float(money(plan['initial_spent_cny'])+money(CAP)))):
        raise RuntimeError('Inherited cumulative budget or stage cap changed')
    b=CampaignBudget(canonical_ledger(cfg),'final',phase_caps=cfg['phase_limits'])
    b.ceiling_override=plan['cumulative_ceiling_cny'];return b


class PolicyEvaluator:
    def __init__(self,deadline,after,backends=()):
        self.deadline,self.after,self.backends=deadline,after,backends
    def __call__(self,problem,source):
        remaining=max(0,self.deadline-time.monotonic())
        return judge.evaluate(source,problem,model_check=True,timeout_s=remaining,task_remaining_s=remaining,
            verification_after_tests=self.after,backends=self.backends)


def verify_frozen(root):
    plan=load(root/'study_plan.json');verify_r4()
    assert plan['r4_snapshot_sha256']==sha(v.ROOT/'snapshot_manifest.json')
    assert {p.relative_to(REPO).as_posix():sha(p) for p in source_files()}==plan['files'],'Pilot source changed'
    prepared=load(root/'prepared.json')
    assert prepared['plan_sha256']==sha(root/'study_plan.json')
    assert prepared['validation_sha256']==sha(root/'validation.json')


def collect(cfg,plan):
    root=Path(cfg['campaign_root']);data=selected();rows=[]
    for condition in dict.fromkeys(j['condition'] for j in plan['jobs']):
        arm=[j for j in plan['jobs'] if j['condition']==condition]
        records=[load(root/'jobs'/condition/(j['pid']+'.json')) for j in arm]
        attempts=[a for r in records for a in r.get('attempts',[])]
        best=[next((a for a in r.get('attempts',[]) if a['idx']==r.get('best_attempt')),{}) for r in records]
        times=[load(root/'jobs'/condition/(j['pid']+'.timing.json')) for j in arm]
        rows.append(dict(condition=condition,framework=arm[0]['framework'],model_id='minimax-m27',n=2,
            recorded=sum(bool(r) for r in records),attempted=sum(bool(r.get('attempts')) for r in records),
            task_seconds=1200,verification_after_tests=arm[0]['verification_after_tests'],
            first_solved=sum(bool(r.get('first_try')) for r in records),solved=sum(bool(r.get('solved')) for r in records),
            repaired=sum(bool(r.get('solved') and not r.get('first_try')) for r in records),
            two_attempts=sum(len(r.get('attempts',[]))==2 for r in records),
            calls=sum(t.get('upstream_requests_entered',0) for t in times),
            mc_executed=sum(bool(a.get('judge',{}).get('model_check',{}).get('executed')) for a in attempts),
            incomplete=sum(a.get('provider_error','').startswith('Generation incomplete/empty:') for a in attempts),
            tests_passed=sum(a.get('tests_passed',0) for a in best),tests_total=sum(len(data[j['pid']].test_cases) for j in arm),
            wall_seconds=round(sum(t.get('wall_seconds',0) for t in times),3)))
    ledger=load(cfg['budget_ledger_path']);before=load(root/'ledger_before_study.json')
    return dict(label='r4 两题形式检查顺序小试验',state=load(root/'study_state.json').get('state','prepared'),
        rows=rows,recorded=sum(r['recorded'] for r in rows),planned=8,
        total_accounted_cny=ledger['spent_cny'],study_increment_cny=round(ledger['spent_cny']-plan['initial_spent_cny'],6),
        diagnostic_increment_cny=round(ledger['spent_cny']-34.011998,6),new_events=len(ledger['events'])-plan['initial_event_count'],
        all_original_events_preserved=ledger['events'][:plan['initial_event_count']]==before['events'] and ledger.get('recoveries',[])==before.get('recoveries',[]),
        halted=ledger.get('halted'),full_r9_started=False,updated_at=stamp())


def report(cfg,plan):
    root=Path(cfg['campaign_root']);s=collect(cfg,plan);atomic_json(root/'study_summary.json',s)
    lines=['# r4两题形式检查顺序试验状态','',f"状态：{s['state']}；已归档{s['recorded']}/8题次。",'',
        '两框架、两检查条件、两固定题，只用MiniMax，最多16次模型请求。数据和裁判均为r4。',
        '', '| 条件 | 已归档 | 首轮通过 | 最终通过 | 修复新增 | 形式检查次数 | 实际请求 | 墙钟秒 |',
        '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for r in s['rows']:
        lines.append(f"| {r['condition']} | {r['recorded']}/2 | {r['first_solved']}/2 | {r['solved']}/2 | {r['repaired']} | {r['mc_executed']} | {r['calls']} | {r['wall_seconds']} |")
    lines += ['',f"本轮计入{s['study_increment_cny']:.6f}元，累计{s['total_accounted_cny']:.6f}元；本轮上限4.50元，累计保护上限{plan['cumulative_ceiling_cny']:.6f}元。",'',
        '计划分母始终为8题次；未完成不能视为成功。两题单次生成不足以证明稳定优势，R8正式表不替换。']
    (root/'实验状态.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    return s


def sync(cfg,plan):
    root=Path(cfg['campaign_root']);report(cfg,plan);MIRROR.mkdir(parents=True,exist_ok=True)
    allowed={'study_plan.json','prepared.json','validation.json','native_preflight.json','cli_offline.json',
        'run_environment.json','study_state.json','study_summary.json','实验状态.md','completion.json'}
    for p in root.rglob('*'):
        if p.is_file() and (p.name in allowed or (p.relative_to(root).parts[0]=='jobs' and p.suffix=='.json')):
            target=MIRROR/p.relative_to(root);target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(p.read_bytes())
    return collect(cfg,plan)


def prepare(cfg):
    root=Path(cfg['campaign_root'])
    if root.exists():raise RuntimeError('Existing study directory is immutable; no automatic preparation overwrite')
    verify_r4();state=load(canonical_ledger(cfg));plan=plan_for(cfg,state)
    root.mkdir(parents=True)
    atomic_json(root/'ledger_before_study.json',state);atomic_json(root/'study_plan.json',plan)
    run=subprocess.run([sys.executable,'-B','-X','utf8','-m','unittest','discover','-s','progress/tests','-p','test_r4_check_order.py','-q'],
        cwd=REPO,capture_output=True,text=True,encoding='utf-8',timeout=120)
    (root/'offline_tests.log').write_text(run.stdout+'\n'+run.stderr,encoding='utf-8')
    if run.returncode:raise RuntimeError(run.stderr[-1800:])
    with ResponsesGateway(mock_text='FUNCTION_BLOCK FB END_FUNCTION_BLOCK',model='offline-fixture') as gateway:
        provider=CodexProvider(gateway,model='offline-fixture',work_root=Path(cfg['platform_root'])/'builds/r4_order_offline',mock=True,timeout=45)
        result=provider.generate([dict(role='user',content='Return the complete function block.')])
        assert result.text.strip()=='FUNCTION_BLOCK FB END_FUNCTION_BLOCK'
        assert len(gateway.requests)==1
        atomic_json(root/'cli_offline.json',dict(passed=True,gateway_requests=1,upstream_requests=0,actual_model=result.model))
    native_preflight(cfg,root)
    assert sha(canonical_ledger(cfg))==plan['initial_ledger_sha256']
    atomic_json(root/'validation.json',dict(passed=True,offline_tests_passed=True,codex_cli_offline_passed=True,
        native_positive_negative_controls_passed=True,model_calls=0,ledger_unchanged=True,
        native_controls_sha256=sha(root/'native_preflight.json'),cli_offline_sha256=sha(root/'cli_offline.json')))
    atomic_json(root/'prepared.json',dict(plan_sha256=sha(root/'study_plan.json'),validation_sha256=sha(root/'validation.json')))
    atomic_json(root/'study_state.json',dict(state='prepared',at=stamp()));sync(cfg,plan)
    print(json.dumps(dict(prepared=True,planned=8,maximum_calls=16,worst_reservation_cny=plan['worst_reservation_cny'],model_calls=0)),flush=True)


def live(cfg):
    root=Path(cfg['campaign_root']);plan=load(root/'study_plan.json');verify_frozen(root)
    if load(root/'study_state.json').get('state')!='prepared' or (root/'active_run.json').exists():
        raise RuntimeError('Study already started or not prepared; no automatic resume')
    if plan_for(cfg,load(root/'ledger_before_study.json'))!=plan:raise RuntimeError('Prepared plan changed')
    proof=load(root/'validation.json')
    if not proof.get('passed') or proof['native_controls_sha256']!=sha(root/'native_preflight.json') or proof['cli_offline_sha256']!=sha(root/'cli_offline.json'):
        raise RuntimeError('Offline validation changed')
    for backend in (support.CodesysBackend(cfg),support.OpenPLCBackend(cfg)):
        control=load(root/'native_preflight.json')[backend.name]
        if control['positive']['platform_identity']!=backend.identity():raise RuntimeError('Compiler identity changed')
    if subprocess.check_output(['git','status','--porcelain'],cwd=REPO):raise RuntimeError('Commit and push the complete pilot first')
    head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip()
    remote=subprocess.check_output(['git','ls-remote','origin','refs/heads/main'],cwd=REPO,text=True,
        env=dict(os.environ,GCM_INTERACTIVE='never',GIT_TERMINAL_PROMPT='0'),timeout=30).split()[0]
    if remote!=head:raise RuntimeError('Pilot must be pushed before generation')
    catalog=credential_check(cfg)
    spec=next(m for m in cfg['models'] if m['id']=='minimax-m27')
    if not catalog['selected_models'].get(spec['model']):raise RuntimeError('Required model missing from read-only catalog')
    budget=budget_for(cfg,plan)
    with ledger_lock(canonical_ledger(cfg)):
        support.no_other_runner(cfg)
        if sha(canonical_ledger(cfg))!=plan['initial_ledger_sha256']:raise RuntimeError('Ledger changed; do not reset baseline')
        atomic_json(root/'active_run.json',dict(**support.current_process_marker(),state='running',entry='r4_check_order.py'))
    atomic_json(root/'run_environment.json',dict(published_git_commit=head,started_at=stamp(),catalog=catalog,paid_request_retries=0,
        r4_snapshot_sha256=plan['r4_snapshot_sha256']))
    pending={j['job_id']:float(money(j['first_upper_cny'])+money(j['repair_upper_cny'])) for j in plan['jobs']}
    data=selected();awake=False;final_state='stopped'
    try:
        if os.name=='nt':awake=bool(ctypes.windll.kernel32.SetThreadExecutionState(0x80000001))
        from stbench.transport import MeteredProvider
        for job in plan['jobs']:
            verify_frozen(root);budget.snapshot()
            atomic_json(root/'study_state.json',dict(state='running',current_job=job['job_id'],at=stamp()));report(cfg,plan)
            folder=root/'jobs'/job['condition'];folder.mkdir(parents=True,exist_ok=True)
            if list(folder.glob(job['pid']+'.*')):raise RuntimeError('Existing job traces; no duplicate request')
            started=time.monotonic();deadline=started+1200
            with ExitStack() as stack:
                transport=MeteredProvider(spec,budget,max_tokens=16384,protocol=spec['generation_protocol'],timeout=420)
                sent=support.guarded_capture(transport,budget,plan,job,pending,folder)
                provider=transport
                if job['framework']=='codex':
                    gateway=stack.enter_context(ResponsesGateway(provider=transport,model=transport.model))
                    provider=CodexProvider(gateway,model=transport.model,work_root=Path(cfg['platform_root'])/'builds/codex_r4_order',timeout=450)
                evaluator=PolicyEvaluator(deadline,job['verification_after_tests'],(support.CodesysBackend(cfg),))
                solver=Solver(provider,max_iters=2,system_prompt=support.system_prompt(cfg,job['framework']),
                    include_ltl=True,model_check=True,task_seconds=max(0,deadline-time.monotonic()),mc_seconds=30,
                    request_window_seconds=450,verification_after_tests=job['verification_after_tests'],evaluator=evaluator,cache_dir=None)
                record=solve_problem(data[job['pid']],solver,log_dir=folder)
            envelope=record.to_dict();envelope.update(study_plan_sha256=sha(root/'study_plan.json'),r4_snapshot_sha256=plan['r4_snapshot_sha256'])
            atomic_json(folder/(job['pid']+'.json'),envelope)
            atomic_json(folder/(job['pid']+'.timing.json'),dict(wall_seconds=time.monotonic()-started,
                upstream_requests_entered=sent[0],job_id=job['job_id'],finished_at=stamp()))
            pending.pop(job['job_id']);budget.snapshot()
            summary=report(cfg,plan)
            if not summary['all_original_events_preserved']:raise RuntimeError('Original ledger prefix changed')
            if record.error and not record.error.startswith('Generation incomplete/empty:'):raise RuntimeError(record.error)
            print(job['job_id'],record.solved,record.stop_reason,flush=True)
        final_state='completed'
        atomic_json(root/'study_state.json',dict(state='completed',at=stamp()))
        summary=report(cfg,plan)
        atomic_json(root/'completion.json',dict(completed=True,recorded=summary['recorded'],max_planned_requests=16,
            actual_new_events=summary['new_events'],all_original_events_preserved=summary['all_original_events_preserved'],
            total_accounted_cny=summary['total_accounted_cny'],study_increment_cny=summary['study_increment_cny']))
    except BaseException as exc:
        atomic_json(root/'study_state.json',dict(state='stopped',error=support.sanitize(str(exc)),at=stamp()))
        raise
    finally:
        if awake:ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
        marker=load(root/'active_run.json');marker.update(state=final_state,ended_at=stamp());atomic_json(root/'active_run.json',marker)
        report(cfg,plan)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('command',choices=['prepare','live','sync','check'])
    args=parser.parse_args();cfg=configuration(str(CONFIG));root=Path(cfg['campaign_root'])
    if args.command=='check':verify_frozen(root);print('PASS frozen pilot and r4')
    elif args.command=='sync':print(json.dumps(sync(cfg,load(root/'study_plan.json')),ensure_ascii=False))
    else:globals()[args.command](cfg)

"""Extend frozen four-group coverage; reuse every prior first candidate, never a repair."""
import argparse
from contextlib import ExitStack
import ctypes
import hashlib
import html
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import zipfile

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / 'agent_dev_r9_stage3'
sys.path.insert(0, str(SOURCE))
sys.path.insert(0, str(SOURCE / 'scripts'))
from stbench.billing import CampaignBudget, canonical_ledger, ledger_lock, money
from stbench.campaign import configuration, credential_check, digest, first_candidate_bound, native_preflight, tasks, PILOT
from stbench.codex_baseline import CodexProvider, ResponsesGateway
from stbench.evaluation import atomic_json
from stbench.harness.engine import Solver, solve_problem
from stbench.harness.prompts import PROMPT_VERSION
from stbench.platforms import CodesysBackend, OpenPLCBackend
from stbench.providers.base import ProviderError
from stbench.transport import MeteredProvider
from campaign_status import load, registered_process_alive
from resume_user_paused_campaign import current_process_marker
import r9_four_group_readiness as prior

CONFIG = REPO / 'progress/config.r9_stage4.json'
PRIOR = Path('E:/PLC_Dev/evidence/real_experiments/r9_four_group_stage3_20261101b')
PROTOCOL = REPO / 'progress/R9第四阶段六题首候选扩展_20261102.md'
TEST = REPO / 'progress/tests/test_stage4_coverage.py'
SYNC = REPO / 'progress/tools/sync_r9_stage4.py'
STAGE_CAP = 6.20
EXPECTED_SOURCE = 'c416ac8fd0ea75dbcc40f37a88e1783d8443b6ee8cbccc347097a2c35fd4f475'
stamp, sha = prior.stamp, prior.sha


def object_sha(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def make_jobs():
    groups = [('custom', 'deepseek-v4pro'), ('codex', 'deepseek-v4pro'),
              ('custom', 'minimax-m27'), ('codex', 'minimax-m27')]
    jobs = []
    for i, pid in enumerate(PILOT):
        order = groups[i % 4:] + groups[:i % 4]
        for fw, mid in order:
            condition = fw + '_' + mid
            jobs.append(dict(pid=pid, framework=fw, model_id=mid, condition=condition,
                job_id=condition + '/' + pid, kind='reused_first' if pid in prior.PIDS else 'fresh'))
    return jobs


def validate_prefix_source(cfg):
    prior.verify_frozen(PRIOR)
    old = configuration(str(prior.CONFIG))
    plan = load(PRIOR / 'study_plan.json')
    env = load(PRIOR / 'run_environment.json')
    if (digest() != EXPECTED_SOURCE or plan.get('source_sha256') != digest() or
            env.get('source_sha256') != digest() or load(PRIOR / 'study_state.json').get('state') != 'completed' or
            load(PRIOR / 'study_summary.json').get('recorded') != 8 or
            plan.get('config_sha256') != sha(prior.CONFIG)):
        raise RuntimeError('Completed, unchanged stage-3 source and all eight records are required')
    if cfg['models'] != old['models'] or cfg['strategy'] != old['strategy']:
        raise RuntimeError('Reuse requires identical model parameters and prompts')
    expected_limits = old['limits'] | dict(max_candidates=1)
    if cfg['limits'] != expected_limits:
        raise RuntimeError('Only candidate count may change for first-candidate coverage')
    for fw in ('custom', 'codex'):
        if hashlib.sha256(prior.system_prompt(cfg, fw).encode()).hexdigest() != plan['prompt_sha256'][fw]:
            raise RuntimeError('First-candidate prompt differs')
    return old


def reuse_descriptor(job, cfg):
    path = PRIOR / 'jobs' / job['condition'] / (job['pid'] + '.json')
    record = load(path)
    spec = next(m for m in cfg['models'] if m['id'] == job['model_id'])
    if (record.get('pid') != job['pid'] or record.get('model') != spec['model'] or
            record.get('prompt_version') != PROMPT_VERSION or record.get('experiment_kind') != 'live' or
            record.get('provider') != ('codex-cli' if job['framework'] == 'codex' else 'openai-compat') or
            not record.get('attempts') or record['attempts'][0].get('idx') != 0):
        raise RuntimeError('Reuse does not identify the actual first attempt: ' + job['job_id'])
    # Check the published mirror, so a local change cannot silently become the reused result.
    mirror = REPO / 'progress/evidence/r9_four_group_stage3_20261101/jobs' / job['condition'] / path.name
    if not mirror.is_file() or mirror.read_bytes() != path.read_bytes():
        raise RuntimeError('Prior record differs from the published evidence mirror')
    return dict(source_record=str(path), source_record_sha256=sha(path),
                first_attempt_sha256=object_sha(record['attempts'][0]), source_run_signature=record['run_signature'])


def build_plan(cfg, state):
    validate_prefix_source(cfg)
    if state.get('halted'):
        raise RuntimeError('Budget is halted; no automatic recovery')
    if cfg['budget_cny'] != 75:
        raise RuntimeError('Original total authorization changed')
    jobs = make_jobs()
    selected = {p.pid: p for _, p, _ in tasks()}
    specs = {m['id']: m for m in cfg['models']}
    for job in jobs:
        if job['kind'] == 'reused_first':
            job.update(reuse_descriptor(job, cfg), first_upper_cny=0.)
        else:
            job['first_upper_cny'] = float(money(first_candidate_bound(specs[job['model_id']], selected[job['pid']], cfg, job['framework'])))
        job['repair_upper_cny'] = 0.
    upper = float(sum((money(j['first_upper_cny']) for j in jobs), money(0)))
    ceiling = min(44.011998, state['spent_cny'] + STAGE_CAP)
    if money(state['spent_cny']) + money(upper) > money(ceiling):
        raise RuntimeError('All sixteen fresh first candidates must fit before starting')
    return dict(kind='six-task first-candidate extension with disclosed historical prefix reuse',
        source_sha256=digest(), config_sha256=sha(CONFIG), initial_spent_cny=state['spent_cny'],
        initial_event_count=len(state['events']), initial_ledger_sha256=sha(canonical_ledger(cfg)),
        study_additional_cap_cny=STAGE_CAP, cumulative_ceiling_cny=ceiling,
        original_diagnostic_baseline_cny=34.011998, original_diagnostic_ceiling_cny=44.011998,
        total_authorized_cny=75, maximum_new_requests=16, planned=24, reused=8, fresh=16,
        max_candidates=1, task_seconds=1200, request_seconds=420, request_window_seconds=450,
        max_output_tokens=16384, mc_seconds=30, verification_after_tests=False,
        worst_reservation_cny=upper, jobs=jobs,
        prefix_scope='All eight stage-3 attempt-0 records; later repair attempts excluded; historical charges not added again')


def scoped_budget(cfg, plan):
    if (plan.get('study_additional_cap_cny') != STAGE_CAP or
            plan.get('original_diagnostic_ceiling_cny') != 44.011998 or
            plan.get('cumulative_ceiling_cny') != min(44.011998, plan['initial_spent_cny'] + STAGE_CAP)):
        raise RuntimeError('Stage cap must stay within the original fixed diagnostic ceiling')
    budget = CampaignBudget(canonical_ledger(cfg), 'final', phase_caps=cfg['phase_limits'])
    budget.ceiling_override = plan['cumulative_ceiling_cny']
    return budget


def capture(transport, budget, plan, job, pending, folder):
    count = prior.guarded_capture(transport, budget, plan, job, pending, folder)
    original = transport.before_send
    def once(messages):
        if count[0]:
            raise ProviderError('Stage-4 first-candidate limit; no second upstream request')
        original(messages)
    transport.before_send = once
    return count


def materialize_reuse(cfg, plan, root):
    for job in plan['jobs']:
        if job['kind'] != 'reused_first':
            continue
        if reuse_descriptor(job, cfg) != {k: job[k] for k in
                ('source_record', 'source_record_sha256', 'first_attempt_sha256', 'source_run_signature')}:
            raise RuntimeError('Historical reuse binding changed')
        first = load(job['source_record'])['attempts'][0]
        envelope = dict(kind='reused_first_candidate', pid=job['pid'], condition=job['condition'],
                        source_record=job['source_record'], source_record_sha256=job['source_record_sha256'],
                        first_attempt_sha256=job['first_attempt_sha256'], source_run_signature=job['source_run_signature'],
                        new_model_requests=0, original_max_candidates=2, first_attempt=first)
        atomic_json(root / 'reused' / job['condition'] / (job['pid'] + '.json'), envelope)


def collect(cfg, plan):
    root = Path(cfg['campaign_root'])
    cases = {p.pid: len(p.test_cases) for _, p, _ in tasks()}
    rows = []
    for condition in dict.fromkeys(j['condition'] for j in plan['jobs']):
        jobs = [j for j in plan['jobs'] if j['condition'] == condition]
        attempts, fresh, reused = [], 0, 0
        for job in jobs:
            folder = 'reused' if job['kind'] == 'reused_first' else 'jobs'
            record = load(root / folder / condition / (job['pid'] + '.json'))
            if not record:
                continue
            if folder == 'reused':
                attempts.append(record['first_attempt']); reused += 1
            else:
                fresh += 1
                if len(record.get('attempts', [])) > 1:
                    raise RuntimeError('First-candidate report cannot consume repair attempts')
                if record.get('attempts'):
                    attempts.append(record['attempts'][0])
        solved = sum(bool(a.get('solved')) for a in attempts)
        rows.append(dict(condition=condition, framework=jobs[0]['framework'], model_id=jobs[0]['model_id'],
            n=6, recorded=fresh+reused, fresh_recorded=fresh, reused=reused, attempted=len(attempts),
            generated=sum(bool(a.get('code')) for a in attempts), first_solved=solved, solved=solved,
            fully_verified=sum(bool(a.get('fully_verified')) for a in attempts), repaired=0, two_attempts=0,
            task_seconds=1200, verification_after_tests=False,
            tests_passed=sum(a.get('tests_passed', 0) for a in attempts), tests_total=sum(cases[j['pid']] for j in jobs),
            mc_executed=sum(bool(a.get('judge', {}).get('model_check', {}).get('executed')) for a in attempts),
            incomplete=sum(a.get('provider_error', '').startswith('Generation incomplete/empty:') for a in attempts)))
    state = load(cfg['budget_ledger_path']); before = load(root / 'ledger_before_study.json')
    return dict(label='R9 第四阶段六题首候选扩展', state=load(root / 'study_state.json').get('state', 'prepared'),
        rows=rows, recorded=sum(r['recorded'] for r in rows), planned=24,
        reused_count=sum(r['reused'] for r in rows), fresh_recorded=sum(r['fresh_recorded'] for r in rows), fresh_planned=16,
        source_sha256=digest(), all_original_events_preserved=state.get('events', [])[:plan['initial_event_count']]==before.get('events')
            and state.get('recoveries', [])==before.get('recoveries', []),
        total_accounted_cny=state['spent_cny'], study_increment_cny=round(state['spent_cny']-plan['initial_spent_cny'], 6),
        diagnostic_increment_cny=round(state['spent_cny']-34.011998, 6), new_events=len(state['events'])-plan['initial_event_count'],
        unknown_reserved_cny=sum(e['reserved_cny'] for e in state['events'] if e.get('status')=='reserved'),
        halted=state.get('halted'), full_r9_started=False, updated_at=stamp())


def write_report(cfg, plan):
    root = Path(cfg['campaign_root']); s = collect(cfg, plan)
    atomic_json(root / 'study_summary.json', s)
    state = load(root / 'study_state.json')
    lines = ['# R9 第四阶段六题首候选扩展', '',
        f"状态：{s['state']}；已归档 {s['recorded']}/24，其中复用 {s['reused_count']}/8、新增 {s['fresh_recorded']}/16。",
        '更新时间：'+stamp(), '', '同一源码与提示、同模型同协议；仅统计第一次生成，原第二候选全部排除。',
        '原八个首候选完整复用，保留失败；只为四道新增代表题发送16次请求。复用不重复计费。', '',
        '|框架|模型|已尝试/6|复用|新增记录|首候选通过|用例通过/75|LTL执行|截断/空正文|',
        '|---|---|---|---|---|---|---|---|---|']
    for r in s['rows']:
        lines.append(f"|{r['framework']}|{r['model_id']}|{r['attempted']}/6|{r['reused']}|{r['fresh_recorded']}|{r['solved']}|{r['tests_passed']}/{r['tests_total']}|{r['mc_executed']}|{r['incomplete']}|")
    lines += ['', f"本阶段新增计入 {s['study_increment_cny']:.6f}/6.20 元；原诊断累计增量 {s['diagnostic_increment_cny']:.6f}/10 元；共享账本 {s['total_accounted_cny']:.6f}/75 元。",
        '费用包含在途与历史未知预留，按配置价格估计，并非供应商实际账单；复用历史费用没有再次加入新增费用。', '',
        '每组固定六题、75条用例；缺失与失败不缩小分母。本轮是小样本准备性扩展，不替代35题正式四组评测。',
        '来源、源码、提示与首候选哈希事前绑定；两批生成的时间和批次差异保留。不能据此宣称稳定优势。',
        '未启动全量R9；人工工艺复核仍待刘晏铭实际确认。']
    if state.get('current_job'): lines += ['', '当前题次：'+state['current_job']]
    if state.get('error'): lines += ['', '停止原因：'+state['error']]
    if state.get('state')=='running': lines += ['', '运行依赖本机开机联网。新故障停止，不自动重试。']
    text='\n'.join(lines)+'\n'
    (root/'实验状态.md').write_text(text, encoding='utf-8')
    (root/'实验状态.html').write_text('<meta charset="utf-8"><meta http-equiv="refresh" content="15"><pre>'+html.escape(text)+'</pre>', encoding='utf-8')
    return s


def tool_manifest():
    return {p.relative_to(REPO).as_posix(): sha(p) for p in (Path(__file__), CONFIG, SYNC, TEST, PROTOCOL)}


def verify_frozen(root):
    prior.verify_frozen(PRIOR)
    manifest = load(root/'snapshot_manifest.json')
    if manifest.get('files') != tool_manifest():
        raise RuntimeError('Stage-4 tools, tests, protocol or configuration changed')
    reused = {p.relative_to(root).as_posix(): sha(p) for p in (root/'reused').glob('*/*.json')}
    if reused != manifest.get('reused_records'):
        raise RuntimeError('Materialized historical first candidates changed')
    for job in load(root/'study_plan.json')['jobs']:
        if job['kind']=='reused_first' and (sha(job['source_record']) != job['source_record_sha256'] or
                object_sha(load(job['source_record'])['attempts'][0]) != job['first_attempt_sha256']):
            raise RuntimeError('Previously paid source evidence changed')


def prepare(cfg, proof_path):
    root = Path(cfg['campaign_root'])
    if root.exists(): raise RuntimeError('Stage directory exists; no overwrite or implicit resume')
    prior.no_other_runner(cfg)
    proof = load(proof_path)
    if not proof.get('passed') or proof.get('source_sha256') != digest() or proof.get('tool_manifest') != tool_manifest():
        raise RuntimeError('Passing current stage-4 guard tests are required')
    budget = CampaignBudget(canonical_ledger(cfg), 'final', phase_caps=cfg['phase_limits'])
    plan = build_plan(cfg, budget.read())
    root.mkdir(parents=True, exist_ok=False)
    atomic_json(root/'study_plan.json', plan)
    (root/'ledger_before_study.json').write_bytes(Path(cfg['budget_ledger_path']).read_bytes())
    atomic_json(root/'validation.json', proof)
    native_preflight(cfg, root)
    enum = load(PRIOR/'enum_native_controls.json')
    if not enum.get('passed') or enum.get('platform_identity') != CodesysBackend(cfg).identity():
        raise RuntimeError('Frozen enum controls or compiler identity changed')
    atomic_json(root/'enum_native_controls.json', enum)
    materialize_reuse(cfg, plan, root)
    atomic_json(root/'snapshot_manifest.json', dict(files=tool_manifest(), source_sha256=digest(),
        prior_manifest_sha256=sha(PRIOR/'snapshot_manifest.json'),
        reused_records={p.relative_to(root).as_posix(): sha(p) for p in (root/'reused').glob('*/*.json')}))
    with zipfile.ZipFile(root/'frozen_stage4_tools.zip', 'x', zipfile.ZIP_DEFLATED) as archive:
        for name in tool_manifest(): archive.write(REPO/name, name)
    atomic_json(root/'prepared.json', dict(source_sha256=digest(), plan_sha256=sha(root/'study_plan.json'),
        validation_sha256=sha(root/'validation.json'), native_controls='passed', model_requests=0, reused=8))
    atomic_json(root/'study_state.json', dict(state='prepared', at=stamp()))
    write_report(cfg, plan)
    print(json.dumps(dict(prepared=True, fresh=16, reused=8, worst_reservation_cny=plan['worst_reservation_cny'], model_requests=0)), flush=True)


def published_head():
    if subprocess.check_output(['git','branch','--show-current'], cwd=REPO, text=True).strip()!='main':
        raise RuntimeError('Start from published main')
    scope = [SOURCE.name+'/'+n for n in ('stbench','scripts','tests','datasets')]+list(tool_manifest())
    if subprocess.check_output(['git','status','--porcelain','--']+scope, cwd=REPO):
        raise RuntimeError('Source and stage-4 tools must be committed')
    head = subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip()
    env = dict(os.environ, GCM_INTERACTIVE='never', GIT_TERMINAL_PROMPT='0')
    remote = subprocess.check_output(['git','ls-remote','origin','refs/heads/main'],cwd=REPO,text=True,env=env,timeout=30).split()[0]
    if remote!=head: raise RuntimeError('Push frozen tools before paid generation')
    return head


def live(cfg):
    root=Path(cfg['campaign_root']);plan=load(root/'study_plan.json');prepared=load(root/'prepared.json')
    verify_frozen(root)
    if (load(root/'study_state.json').get('state')!='prepared' or (root/'active_run.json').exists() or
            prepared.get('plan_sha256')!=sha(root/'study_plan.json') or
            prepared.get('validation_sha256')!=sha(root/'validation.json') or
            build_plan(cfg,load(root/'ledger_before_study.json'))!=plan):
        raise RuntimeError('Prepared plan changed or already started; no automatic resume')
    for backend in (CodesysBackend(cfg),OpenPLCBackend(cfg)):
        row=load(root/'native_preflight.json').get(backend.name,{})
        if row.get('positive',{}).get('status')!='passed' or row.get('negative',{}).get('status')!='failed' or row['positive']['platform_identity']!=backend.identity():
            raise RuntimeError('Native controls or compiler identity changed')
    head=published_head();catalog=credential_check(cfg)
    if not all(catalog['selected_models'].values()): raise RuntimeError('Approved models absent from catalog')
    budget=scoped_budget(cfg,plan)
    with ledger_lock(canonical_ledger(cfg)):
        prior.no_other_runner(cfg)
        if sha(canonical_ledger(cfg))!=plan['initial_ledger_sha256']: raise RuntimeError('Ledger changed; do not reset baseline')
        atomic_json(root/'active_run.json',dict(**current_process_marker(),state='running',entry='r9_stage4_coverage.py',source_sha256=digest()))
    atomic_json(root/'run_environment.json',dict(published_git_commit=head,source_sha256=digest(),started_at=stamp(),catalog=catalog,paid_request_retries=0))
    fresh=[j for j in plan['jobs'] if j['kind']=='fresh'];pending={j['job_id']:j['first_upper_cny'] for j in fresh}
    selected={p.pid:p for _,p,_ in tasks()};specs={m['id']:m for m in cfg['models']}
    awake=bool(ctypes.windll.kernel32.SetThreadExecutionState(0x80000001)) if os.name=='nt' else False
    final='stopped'
    atomic_json(root/'study_state.json',dict(state='running',at=stamp()))
    try:
        for job in fresh:
            verify_frozen(root);budget.snapshot()
            atomic_json(root/'study_state.json',dict(state='running',current_job=job['job_id'],at=stamp()))
            write_report(cfg,plan)
            folder=root/'jobs'/job['condition'];folder.mkdir(parents=True,exist_ok=True)
            if list(folder.glob(job['pid']+'.*')): raise RuntimeError('Existing request traces; refuse duplicate generation')
            started=time.monotonic();spec=specs[job['model_id']]
            with ExitStack() as stack:
                transport=MeteredProvider(spec,budget,max_tokens=16384,protocol=spec['generation_protocol'],timeout=420)
                sent=capture(transport,budget,plan,job,pending,folder);provider=transport
                if job['framework']=='codex':
                    gateway=stack.enter_context(ResponsesGateway(provider=transport,model=spec['model']))
                    provider=CodexProvider(gateway,model=spec['model'],work_root=Path(cfg['platform_root'])/'builds/codex_r9_stage3',timeout=450)
                solver=Solver(provider,max_iters=1,system_prompt=prior.system_prompt(cfg,job['framework']),include_ltl=True,
                    model_check=True,verification_after_tests=False,task_seconds=1200,mc_seconds=30,request_window_seconds=450,
                    backends=(CodesysBackend(cfg),),cache_dir=None)
                record=solve_problem(selected[job['pid']],solver,log_dir=folder)
            atomic_json(folder/(job['pid']+'.timing.json'),dict(wall_seconds=time.monotonic()-started,upstream_requests_entered=sent[0],finished_at=stamp()))
            pending.pop(job['job_id']);print(job['job_id'],record.solved,record.stop_reason,flush=True)
            budget.snapshot()
            if record.error and not record.error.startswith('Generation incomplete/empty:'): raise RuntimeError(record.error)
            if not collect(cfg,plan)['all_original_events_preserved']: raise RuntimeError('Original budget history changed')
            write_report(cfg,plan)
        final='completed';atomic_json(root/'study_state.json',dict(state=final,at=stamp()))
    except BaseException as error:
        atomic_json(root/'study_state.json',dict(state='stopped',error=prior.sanitize(str(error)),at=stamp()));raise
    finally:
        if awake: ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
        marker=load(root/'active_run.json');marker.update(state=final,ended_at=stamp());atomic_json(root/'active_run.json',marker)
        write_report(cfg,plan)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--prepare',action='store_true');parser.add_argument('--live',action='store_true')
    parser.add_argument('--validation',type=Path);args=parser.parse_args();cfg=configuration(str(CONFIG))
    if args.prepare and not args.live and args.validation: prepare(cfg,args.validation)
    elif args.live and not args.prepare: live(cfg)
    else: parser.error('Choose prepare with validation, or live')


if __name__=='__main__':main()

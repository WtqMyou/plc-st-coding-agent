"""Frozen two-factor MiniMax repair diagnosis, within the original diagnostic cap."""
from contextlib import ExitStack
import argparse
import ctypes
from datetime import datetime
import hashlib
import html
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from stbench.billing import CampaignBudget, canonical_ledger, ledger_lock, money
from stbench.campaign import (configuration, credential_check, digest, first_candidate_bound,
                              native_preflight, tasks)
from stbench.codex_baseline import CodexProvider, ResponsesGateway
from stbench.evaluation import atomic_json
from stbench.harness.engine import Solver, solve_problem
from stbench.harness.prompts import build_system_prompt
from stbench.platforms import CodesysBackend, OpenPLCBackend
from stbench.providers.base import ProviderError
from stbench.transport import MeteredProvider
from campaign_status import load, registered_process_alive
from resume_user_paused_campaign import current_process_marker

PIDS = ('self-medium-03', 'public-hard-04')
STUDY_CAP = 8.0
REPAIR_INPUT_BYTES = 131072  # Includes the transport's 4096-byte accounting margin.
CONFIG = ROOT / 'config.r9_repair.json'


def stamp():
    return datetime.now().astimezone().isoformat()


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def system_prompt(cfg, framework):
    return build_system_prompt() + ('\n' + cfg['strategy']['extra_instruction']
                                    if framework == 'custom' else '')


def make_jobs():
    conditions = [(seconds, defer, fw) for seconds in (600, 1200)
                  for defer in (False, True) for fw in ('custom', 'codex')]
    jobs = []
    for i, pid in enumerate(PIDS):
        for seconds, defer, fw in (conditions if i == 0 else conditions[::-1]):
            condition = f"{fw}_{seconds}_{'tests_first' if defer else 'all_compiled'}"
            jobs.append(dict(pid=pid, framework=fw, task_seconds=seconds,
                             verification_after_tests=defer, condition=condition,
                             job_id=condition + '/' + pid))
    return jobs


def build_plan(cfg, state, origin, validation):
    if (origin['budget_baseline_cny'] != 34.011998 or
            origin['diagnostic_cumulative_ceiling_cny'] != 44.011998 or
            origin['diagnostic_incremental_cap_cny'] != 10 or state.get('halted')):
        raise RuntimeError('Original diagnostic boundary or unhalted ledger is required')
    limits = cfg['limits']
    if tuple(limits[k] for k in ('max_candidates', 'request_seconds', 'codex_overhead_seconds',
                                'mc_seconds', 'max_output_tokens', 'compile_seconds')) != (2, 420, 30, 30, 16384, 120):
        raise RuntimeError('Common repair limits changed')
    required_checks = ('cli_tree_deadline', 'upstream_failure_aborts_cli', 'single_upstream_request',
                       'full_request_window', 'request_window_keeps_best', 'genuine_timeout_keeps_halt')
    if (not validation.get('passed') or validation.get('source_sha256') != digest() or
            not all(validation.get('deadline_checks', {}).get(k) is True for k in required_checks) or
            validation.get('request_window_seconds') != 450):
        raise RuntimeError('Current full offline validation is required')
    selected = {p.pid: p for _, p, _ in tasks()}
    spec = cfg['models'][1]
    if spec['model'] != 'MiniMax-M2.7' or spec['generation_protocol'] != 'chat':
        raise RuntimeError('Frozen MiniMax Chat model is required')
    repair_bound = float(money((REPAIR_INPUT_BYTES * spec['input_cny_per_million'] +
                                16384 * spec['output_cny_per_million']) / 1e6))
    jobs = make_jobs()
    for job in jobs:
        job['first_upper_cny'] = float(money(first_candidate_bound(
            spec, selected[job['pid']], cfg, job['framework'])))
        job['repair_upper_cny'] = repair_bound
    upper = float(sum((money(j['first_upper_cny']) + money(repair_bound) for j in jobs), money(0)))
    ceiling = min(origin['diagnostic_cumulative_ceiling_cny'], state['spent_cny'] + STUDY_CAP)
    if money(state['spent_cny']) + money(upper) > money(ceiling):
        raise RuntimeError('All first and repair reservations must fit before starting')
    return dict(kind='two-task factorial repair diagnosis, not full formal benchmark',
                source_sha256=digest(), config_sha256=sha(CONFIG),
                initial_spent_cny=state['spent_cny'], initial_event_count=len(state['events']),
                initial_ledger_sha256=sha(canonical_ledger(cfg)), study_additional_cap_cny=STUDY_CAP,
                cumulative_ceiling_cny=ceiling, original_diagnostic_ceiling_cny=44.011998,
                original_diagnostic_baseline_cny=34.011998, total_authorized_cny=75,
                maximum_requests=32, max_candidates=2, request_seconds=420, request_window_seconds=450,
                mc_seconds=30, max_output_tokens=16384, repair_input_bytes=REPAIR_INPUT_BYTES,
                worst_reservation_cny=upper, model=spec['model'], protocol='chat',
                prompt_sha256={fw: hashlib.sha256(system_prompt(cfg, fw).encode()).hexdigest()
                               for fw in ('custom', 'codex')}, jobs=jobs)


def study_budget(cfg, plan):
    if (plan['study_additional_cap_cny'] != STUDY_CAP or
            plan['original_diagnostic_ceiling_cny'] != 44.011998 or
            plan['cumulative_ceiling_cny'] != min(44.011998, plan['initial_spent_cny'] + STUDY_CAP)):
        raise RuntimeError('Study cap cannot reset or expand the original diagnostic allocation')
    budget = CampaignBudget(canonical_ledger(cfg), 'final', phase_caps=cfg['phase_limits'])
    budget.ceiling_override = plan['cumulative_ceiling_cny']
    return budget


def frozen_files():
    files = [p for folder in ('stbench', 'scripts', 'tests', 'datasets')
             for p in (ROOT / folder).rglob('*')
             if p.is_file() and '__pycache__' not in p.parts and p.suffix not in ('.pyc', '.tmp')]
    return sorted(files + [CONFIG, ROOT / 'ORIGIN_R8.json',
                           ROOT / 'docs/R9多轮修复小规模对照方案_20261101.md'])


def verify_frozen(root):
    manifest = load(root / 'snapshot_manifest.json')
    if not manifest.get('files'):
        raise RuntimeError('Frozen source manifest missing')
    if set(manifest['files']) != {p.relative_to(ROOT).as_posix() for p in frozen_files()}:
        raise RuntimeError('Frozen file set changed')
    if any(sha(ROOT / name) != expected for name, expected in manifest['files'].items()):
        raise RuntimeError('Frozen source, tests, scripts or data changed')


def no_other_runner(cfg):
    parent = Path(cfg['platform_root']) / 'evidence/real_experiments'
    if any(registered_process_alive(load(p)) for p in parent.glob('*/active_run.json')):
        raise RuntimeError('An experiment runner is already alive')


def sanitize(text):
    for name in ('DMXAPI_API_KEY', 'OPENAI_API_KEY', 'GH_TOKEN', 'GITHUB_TOKEN'):
        value = os.environ.get(name, '')
        if len(value) > 12:
            text = text.replace(value, '[redacted]')
    return re.sub(r'\b(?:sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})',
                  '[redacted]', text)


def guarded_capture(transport, budget, plan, job, pending, folder):
    count = [0]

    def before_send(messages):
        if count[0] >= 2:
            raise ProviderError('Study request guard: at most one initial call and one repair')
        bound = job['first_upper_cny'] if count[0] == 0 else job['repair_upper_cny']
        if money(transport.upper(messages)) > money(bound):
            raise ProviderError('Study input guard: frozen request bound exceeded; no request sent')
        protected = sum((money(v) for k, v in pending.items() if k != job['job_id']), money(0))
        if count[0] == 0:
            protected += money(job['repair_upper_cny'])
        budget.protected_cny = float(protected)
        count[0] += 1
        path = folder / f"{job['pid']}.request_{count[0]:02}.json"
        if path.exists():
            raise ProviderError('Study request trace already exists; refusing duplicate call')
        public = dict(model=transport.model, protocol=transport.protocol, max_tokens=16384,
                      timeout_seconds=420, messages=[{k: m[k] for k in ('role', 'content') if k in m}
                                                    for m in messages])
        atomic_json(path, json.loads(sanitize(json.dumps(public, ensure_ascii=False))))

    def response(data, protocol):
        choice = (data.get('choices') or [{}])[0]
        message = choice.get('message') or {}
        safe = dict(model=data.get('model'), usage=data.get('usage'), protocol=protocol,
                    finish_reason=choice.get('finish_reason'),
                    message={k: message[k] for k in ('content', 'reasoning_content', 'reasoning_details') if k in message})
        atomic_json(folder / f"{job['pid']}.response_{count[0]:02}.json",
                    json.loads(sanitize(json.dumps(safe, ensure_ascii=False))))

    transport.before_send = before_send
    transport.response_observer = response
    return count


def collect(cfg, plan):
    root = Path(cfg['campaign_root'])
    rows = []
    case_counts = {p.pid: len(p.test_cases) for _, p, _ in tasks()}
    for condition in dict.fromkeys(j['condition'] for j in plan['jobs']):
        jobs = [j for j in plan['jobs'] if j['condition'] == condition]
        records = [load(root / 'jobs' / condition / (j['pid'] + '.json')) for j in jobs]
        best = [next((a for a in r.get('attempts', []) if a.get('idx') == r.get('best_attempt')), {})
                for r in records]
        first = jobs[0]
        rows.append(dict(condition=condition, framework=first['framework'], task_seconds=first['task_seconds'],
                         verification_after_tests=first['verification_after_tests'], n=len(jobs),
                         recorded=sum(bool(r) for r in records),
                         attempted=sum(bool(r.get('attempts')) for r in records),
                         generated=sum(any(a.get('code') for a in r.get('attempts', [])) for r in records),
                         first_solved=sum(bool(r.get('first_try')) for r in records),
                         solved=sum(bool(r.get('solved')) for r in records),
                         repaired=sum(bool(r.get('solved') and not r.get('first_try')) for r in records),
                         calls=sum(len(r.get('attempts', [])) for r in records),
                         two_attempts=sum(len(r.get('attempts', [])) >= 2 for r in records),
                         window_stops=sum(r.get('stop_reason') == 'insufficient_request_window' for r in records),
                         mc_executed=sum(bool(a.get('judge', {}).get('mc_executed'))
                                         for r in records for a in r.get('attempts', [])),
                         fully_verified=sum(bool(r.get('fully_verified')) for r in records),
                         tests_passed=sum(a.get('tests_passed', 0) for a in best),
                         stop_reasons={reason: sum(r.get('stop_reason') == reason for r in records)
                                       for reason in sorted({r['stop_reason'] for r in records if r.get('stop_reason')})},
                         tests_total=sum(case_counts[j['pid']] for j in jobs)))
    ledger = load(cfg['budget_ledger_path'])
    before = load(root / 'ledger_before_study.json')
    preserved = (ledger.get('events', [])[:plan['initial_event_count']] == before.get('events') and
                 ledger.get('recoveries', []) == before.get('recoveries', []))
    contrasts = []
    for fw in ('custom', 'codex'):
        own = [r for r in rows if r['framework'] == fw]
        pairs = [('time_1200_minus_600', f'gate={gate}',
                  next(r for r in own if r['task_seconds'] == 1200 and r['verification_after_tests'] == gate),
                  next(r for r in own if r['task_seconds'] == 600 and r['verification_after_tests'] == gate))
                 for gate in (False, True)]
        pairs += [('tests_first_minus_all_compiled', f'seconds={seconds}',
                   next(r for r in own if r['task_seconds'] == seconds and r['verification_after_tests']),
                   next(r for r in own if r['task_seconds'] == seconds and not r['verification_after_tests']))
                  for seconds in (600, 1200)]
        for factor, held, treatment, control in pairs:
            contrasts.append(dict(framework=fw, factor=factor, held=held,
                complete=treatment['attempted'] == control['attempted'] == 2,
                deltas={key: treatment[key] - control[key]
                        for key in ('first_solved', 'solved', 'repaired', 'two_attempts', 'mc_executed', 'window_stops')}))
    return dict(state=load(root / 'study_state.json').get('state', 'prepared'), rows=rows, contrasts=contrasts,
                recorded=sum(r['recorded'] for r in rows), planned=len(plan['jobs']),
                source_sha256=plan['source_sha256'], all_original_events_preserved=preserved,
                total_accounted_cny=ledger.get('spent_cny'),
                study_increment_cny=round(ledger.get('spent_cny', plan['initial_spent_cny']) - plan['initial_spent_cny'], 6),
                diagnostic_increment_cny=round(ledger.get('spent_cny', 34.011998) - 34.011998, 6),
                original_diagnostic_ceiling_cny=44.011998, study_cumulative_ceiling_cny=plan['cumulative_ceiling_cny'],
                halted=ledger.get('halted'), unknown_reserved_cny=sum(e['reserved_cny'] for e in ledger.get('events', [])
                                                                  if e.get('status') == 'reserved'),
                new_events=len(ledger.get('events', [])) - plan['initial_event_count'],
                full_r9_started=False, updated_at=stamp())


def write_report(cfg, plan):
    root = Path(cfg['campaign_root'])
    summary = collect(cfg, plan)
    atomic_json(root / 'study_summary.json', summary)
    state = summary['state']
    current = load(root / 'study_state.json').get('current_job', '')
    lines = ['# R9 多轮修复小规模对照状态', '',
             f"状态：{state}；已保存 {summary['recorded']}/{summary['planned']} 个题次。更新时间：{stamp()}。", '',
             '固定 MiniMax 和各框架原提示；两题 × 两框架 × 两时间预算 × 两检查策略，最多两次生成。',
             'all_compiled：功能测试后仍检查编译成功的失败候选；tests_first：仅在功能全通过后检查 LTL。',
             '两组均先进行静态与原生编译门控；策略还会影响后续修复反馈，不是纯耗时差异。', '',
             '|框架|单题秒数|暂缓失败候选的 LTL|已尝试/2|首轮通过|最终通过|修复新增成功|实际两次尝试|窗口不足停止|',
             '|---|---|---|---|---|---|---|---|---|']
    for r in summary['rows']:
        lines.append(f"|{r['framework']}|{r['task_seconds']}|{r['verification_after_tests']}|{r['attempted']}/2|"
                     f"{r['first_solved']}|{r['solved']}|{r['repaired']}|{r['two_attempts']}|{r['window_stops']}|")
    lines += ['', f"本阶段增量 {summary['study_increment_cny']:.6f}/8 元；原诊断累计增量 "
              f"{summary['diagnostic_increment_cny']:.6f}/10 元；共享账本 {summary['total_accounted_cny']:.6f}/75 元。",
              '金额包含保留预留，不是供应商实际账单。原有费用事件和未知预留不得清空。', '',
              '两题单次随机生成的小样本，不提供稳定优势或统计显著性结论；R8 正式结果保持独立。',
              '缺失、网络失败和未获得代码的题次仍保留在预设分母中，不自动重试或补跑。',
              '未启动完整 R9。五道工业题的人工工艺结论仍待刘晏铭实际审核。']
    if current:
        lines += ['', '当前题次：' + current]
    if state == 'running':
        lines += ['', '本机运行，需保持电脑开机联网，避免合盖睡眠。GitHub 展示的是同步快照。']
    if state == 'stopped':
        lines += ['', '停止原因：' + load(root / 'study_state.json').get('error', '需要检查')]
    text = '\n'.join(lines) + '\n'
    (root / '实验状态.md').write_text(text, encoding='utf-8')
    (root / '实验状态.html').write_text('<meta charset="utf-8"><meta http-equiv="refresh" content="15">'
        '<style>body{font:17px/1.7 system-ui;margin:36px}pre{white-space:pre-wrap}</style><pre>' +
        html.escape(text) + '</pre>', encoding='utf-8')
    return summary


def prepare(cfg, validation_path):
    root = Path(cfg['campaign_root'])
    if root.exists():
        raise RuntimeError('Study directory already exists; refuse overwrite or implicit resume')
    no_other_runner(cfg)
    budget = CampaignBudget(canonical_ledger(cfg), 'final', phase_caps=cfg['phase_limits'])
    state = budget.read()
    proof = load(validation_path)
    plan = build_plan(cfg, state, load(ROOT / 'ORIGIN_R8.json'), proof)
    root.mkdir(parents=True, exist_ok=False)
    atomic_json(root / 'study_plan.json', plan)
    (root / 'ledger_before_study.json').write_bytes(Path(cfg['budget_ledger_path']).read_bytes())
    atomic_json(root / 'validation.json', proof)
    native_preflight(cfg, root)
    files = frozen_files()
    atomic_json(root / 'snapshot_manifest.json', dict(files={p.relative_to(ROOT).as_posix(): sha(p) for p in files}))
    with zipfile.ZipFile(root / 'frozen_source.zip', 'x', zipfile.ZIP_DEFLATED) as archive:
        for p in files:
            archive.write(p, p.relative_to(ROOT).as_posix())
    atomic_json(root / 'prepared.json', dict(native_controls='passed', generation_requests=0,
                source_sha256=digest(), plan_sha256=sha(root / 'study_plan.json'),
                validation_sha256=sha(root / 'validation.json')))
    atomic_json(root / 'study_state.json', dict(state='prepared', at=stamp()))
    write_report(cfg, plan)
    print(json.dumps(dict(prepared=True, jobs=16, maximum_requests=32,
                         worst_reservation_cny=plan['worst_reservation_cny'], model_requests=0)), flush=True)


def published_head():
    repo = ROOT.parent
    if subprocess.check_output(['git', 'branch', '--show-current'], cwd=repo, text=True).strip() != 'main':
        raise RuntimeError('Study must start from the published main branch')
    scope = ['agent_dev_r9/' + p for p in ('stbench', 'scripts', 'tests', 'datasets', 'config.r9_repair.json')]
    if subprocess.check_output(['git', 'status', '--porcelain', '--'] + scope, cwd=repo):
        raise RuntimeError('Study code and configuration must be committed first')
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
    env = dict(os.environ, GCM_INTERACTIVE='never', GIT_TERMINAL_PROMPT='0')
    remote = subprocess.check_output(['git', 'ls-remote', 'origin', 'refs/heads/main'], cwd=repo,
                                     text=True, env=env, timeout=30).split()[0]
    if remote != head:
        raise RuntimeError('Study code must be pushed before paid generation starts')
    return head


def live(cfg):
    root = Path(cfg['campaign_root'])
    plan = load(root / 'study_plan.json')
    prepared = load(root / 'prepared.json')
    verify_frozen(root)
    if (prepared.get('plan_sha256') != sha(root / 'study_plan.json') or
            prepared.get('validation_sha256') != sha(root / 'validation.json') or
            load(root / 'study_state.json').get('state') != 'prepared' or (root / 'active_run.json').exists()):
        raise RuntimeError('Prepared study changed or has already started; no automatic resume')
    if build_plan(cfg, load(root / 'ledger_before_study.json'), load(ROOT / 'ORIGIN_R8.json'),
                  load(root / 'validation.json')) != plan:
        raise RuntimeError('Frozen plan differs from the current source, configuration or ledger')
    native = load(root / 'native_preflight.json')
    for backend in (CodesysBackend(cfg), OpenPLCBackend(cfg)):
        row = native.get(backend.name, {})
        if (row.get('positive', {}).get('status') != 'passed' or row.get('negative', {}).get('status') != 'failed' or
                row['positive'].get('platform_identity') != backend.identity()):
            raise RuntimeError('Native compiler control or identity changed')
    head = published_head()
    catalog = credential_check(cfg)
    if not all(catalog['selected_models'].values()):
        raise RuntimeError('Approved models absent from the catalog')
    budget = study_budget(cfg, plan)
    with ledger_lock(canonical_ledger(cfg)):
        no_other_runner(cfg)
        if sha(canonical_ledger(cfg)) != plan['initial_ledger_sha256']:
            raise RuntimeError('Ledger changed since preparation; do not reset the study baseline')
        atomic_json(root / 'active_run.json', dict(**current_process_marker(), state='running',
                    entry='r9_repair_study.py', source_sha256=digest()))
    atomic_json(root / 'run_environment.json', dict(published_git_commit=head, source_sha256=digest(),
                python=sys.version, started_at=stamp(), paid_request_retries=0, catalog=catalog))
    pending = {j['job_id']: j['first_upper_cny'] + j['repair_upper_cny'] for j in plan['jobs']}
    selected = {p.pid: p for _, p, _ in tasks()}
    awake = bool(ctypes.windll.kernel32.SetThreadExecutionState(0x80000001)) if os.name == 'nt' else False
    final_state = 'stopped'
    atomic_json(root / 'study_state.json', dict(state='running', at=stamp()))
    try:
        for job in plan['jobs']:
            verify_frozen(root)
            budget.snapshot()
            atomic_json(root / 'study_state.json', dict(state='running', current_job=job['job_id'], at=stamp()))
            write_report(cfg, plan)
            folder = root / 'jobs' / job['condition']
            folder.mkdir(parents=True, exist_ok=True)
            if list(folder.glob(job['pid'] + '.*')):
                raise RuntimeError('Job traces already exist; no automatic duplicate generation')
            start = time.monotonic()
            with ExitStack() as stack:
                transport = MeteredProvider(cfg['models'][1], budget, max_tokens=16384, protocol='chat', timeout=420)
                sent = guarded_capture(transport, budget, plan, job, pending, folder)
                provider = transport
                if job['framework'] == 'codex':
                    gateway = stack.enter_context(ResponsesGateway(provider=transport, model=transport.model))
                    provider = CodexProvider(gateway, model=transport.model,
                        work_root=Path(cfg['platform_root']) / 'builds/codex_r9_repair', timeout=450)
                solver = Solver(provider, max_iters=2, system_prompt=system_prompt(cfg, job['framework']),
                    include_ltl=True, model_check=True, task_seconds=job['task_seconds'], mc_seconds=30,
                    verification_after_tests=job['verification_after_tests'], request_window_seconds=450,
                    backends=(CodesysBackend(cfg),), cache_dir=None)
                record = solve_problem(selected[job['pid']], solver, log_dir=folder)
            atomic_json(folder / (job['pid'] + '.timing.json'), dict(wall_seconds=time.monotonic() - start,
                upstream_requests_entered=sent[0], finished_at=stamp(), job_id=job['job_id']))
            pending.pop(job['job_id'])
            print(job['job_id'], record.solved, record.stop_reason, flush=True)
            budget.snapshot()  # Unknown usage stops the entire study and preserves its reservation.
            if record.error and not record.error.startswith('Generation incomplete/empty:'):
                raise RuntimeError(record.error)
            if not collect(cfg, plan)['all_original_events_preserved']:
                raise RuntimeError('Original ledger prefix changed')
            write_report(cfg, plan)
        final_state = 'completed'
        atomic_json(root / 'study_state.json', dict(state=final_state, at=stamp()))
    except BaseException as error:
        atomic_json(root / 'study_state.json', dict(state='stopped', error=sanitize(str(error)), at=stamp()))
        raise
    finally:
        if awake:
            ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
        marker = load(root / 'active_run.json')
        marker.update(state=final_state, ended_at=stamp())
        atomic_json(root / 'active_run.json', marker)
        write_report(cfg, plan)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepare', action='store_true')
    parser.add_argument('--live', action='store_true')
    parser.add_argument('--report', action='store_true')
    parser.add_argument('--validation', type=Path)
    args = parser.parse_args()
    cfg = configuration(str(CONFIG))
    if sum((args.prepare, args.live, args.report)) != 1:
        parser.error('Choose exactly one action')
    if args.prepare:
        if not args.validation:
            parser.error('Preparation requires validation')
        prepare(cfg, args.validation)
    elif args.live:
        live(cfg)
    else:
        write_report(cfg, load(Path(cfg['campaign_root']) / 'study_plan.json'))


if __name__ == '__main__':
    main()

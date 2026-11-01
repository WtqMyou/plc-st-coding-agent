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
STUDY_CAP = 7.5
REPAIR_INPUT_BYTES = 65536  # Includes the transport's 4096-byte accounting margin.
CONFIG = ROOT / 'config.r9_stage3.json'


def stamp():
    return datetime.now().astimezone().isoformat()


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def system_prompt(cfg, framework):
    return build_system_prompt() + ('\n' + cfg['strategy']['extra_instruction']
                                    if framework == 'custom' else '')


def make_jobs():
    conditions = [('custom','deepseek-v4pro'), ('codex','deepseek-v4pro'),
                  ('custom','minimax-m27'), ('codex','minimax-m27')]
    jobs = []
    for i, pid in enumerate(PIDS):
        for fw, mid in (conditions if i == 0 else conditions[::-1]):
            condition = fw + '_' + mid
            jobs.append(dict(pid=pid, framework=fw, model_id=mid, task_seconds=1200,
                             verification_after_tests=False, condition=condition, job_id=condition+'/'+pid))
    return jobs


def build_plan(cfg, state, origin, validation):
    if (origin['budget_baseline_cny'] != 34.011998 or origin['diagnostic_cumulative_ceiling_cny'] != 44.011998
            or origin['diagnostic_incremental_cap_cny'] != 10 or state.get('halted')):
        raise RuntimeError('Original diagnostic boundary or unhalted ledger changed')
    if tuple(cfg['limits'][k] for k in ('max_candidates','task_seconds','request_seconds','codex_overhead_seconds',
            'mc_seconds','max_output_tokens','compile_seconds')) != (2,1200,420,30,30,16384,120):
        raise RuntimeError('Common bounded readiness limits changed')
    required=('cli_tree_deadline','upstream_failure_aborts_cli','single_upstream_request',
              'full_request_window','request_window_keeps_best','genuine_timeout_keeps_halt')
    if (not validation.get('passed') or validation.get('source_sha256') != digest() or
            not all(validation.get('deadline_checks',{}).get(k) is True for k in required)):
        raise RuntimeError('Current full offline validation required')
    selected={p.pid:p for _,p,_ in tasks()};specs={m['id']:m for m in cfg['models']}
    jobs=make_jobs()
    for job in jobs:
        spec=specs[job['model_id']]
        job['first_upper_cny']=float(money(first_candidate_bound(spec,selected[job['pid']],cfg,job['framework'])))
        job['repair_upper_cny']=float(money((REPAIR_INPUT_BYTES*spec['input_cny_per_million']+
            16384*spec['output_cny_per_million'])/1e6))
    upper=float(sum((money(j['first_upper_cny'])+money(j['repair_upper_cny']) for j in jobs),money(0)))
    ceiling=min(44.011998,state['spent_cny']+STUDY_CAP)
    if money(state['spent_cny'])+money(upper)>money(ceiling):
        raise RuntimeError('All eight jobs and repairs must fit before starting')
    return dict(kind='four-group two-task readiness diagnosis; not a formal 35-task benchmark',
        source_sha256=digest(),config_sha256=sha(CONFIG),initial_spent_cny=state['spent_cny'],
        initial_event_count=len(state['events']),initial_ledger_sha256=sha(canonical_ledger(cfg)),
        study_additional_cap_cny=STUDY_CAP,cumulative_ceiling_cny=ceiling,
        original_diagnostic_ceiling_cny=44.011998,original_diagnostic_baseline_cny=34.011998,
        total_authorized_cny=75,maximum_requests=16,max_candidates=2,request_seconds=420,
        request_window_seconds=450,mc_seconds=30,max_output_tokens=16384,repair_input_bytes=REPAIR_INPUT_BYTES,
        worst_reservation_cny=upper,protocols={mid:s['generation_protocol'] for mid,s in specs.items()},
        prompt_sha256={fw:hashlib.sha256(system_prompt(cfg,fw).encode()).hexdigest() for fw in ('custom','codex')},jobs=jobs)


def study_budget(cfg, plan):
    if (plan['study_additional_cap_cny'] != STUDY_CAP or
            plan['original_diagnostic_ceiling_cny'] != 44.011998 or
            plan['cumulative_ceiling_cny'] != min(44.011998, plan['initial_spent_cny'] + STUDY_CAP)):
        raise RuntimeError('Study cap cannot reset or expand the original diagnostic allocation')
    budget = CampaignBudget(canonical_ledger(cfg), 'final', phase_caps=cfg['phase_limits'])
    budget.ceiling_override = plan['cumulative_ceiling_cny']
    return budget


def frozen_files():
    files=[p for folder in ('stbench','scripts','tests','datasets') for p in (ROOT/folder).rglob('*')
           if p.is_file() and '__pycache__' not in p.parts and p.suffix not in ('.pyc','.tmp')]
    return sorted(files+[CONFIG,ROOT/'ORIGIN_R8.json',ROOT/'ORIGIN_STAGE3.json',
                         ROOT/'docs/R9第三阶段四组准备性实验_20261101.md'])


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
        if protocol == 'responses':
            message = dict(content=''.join(c.get('text','') for item in data.get('output',[]) if item.get('type')=='message' for c in item.get('content',[]) if c.get('type')=='output_text'))
        safe = dict(model=data.get('model'), usage=data.get('usage'), protocol=protocol,
                    finish_reason=data.get('status') if protocol=='responses' else choice.get('finish_reason'),
                    message={k: message[k] for k in ('content', 'reasoning_content', 'reasoning_details') if k in message})
        atomic_json(folder / f"{job['pid']}.response_{count[0]:02}.json",
                    json.loads(sanitize(json.dumps(safe, ensure_ascii=False))))

    transport.before_send = before_send
    transport.response_observer = response
    return count


def collect(cfg, plan):
    root=Path(cfg['campaign_root']);rows=[];case_counts={p.pid:len(p.test_cases) for _,p,_ in tasks()}
    for condition in dict.fromkeys(j['condition'] for j in plan['jobs']):
        jobs=[j for j in plan['jobs'] if j['condition']==condition]
        records=[load(root/'jobs'/condition/(j['pid']+'.json')) for j in jobs]
        attempts=[a for r in records for a in r.get('attempts',[])]
        best=[next((a for a in r.get('attempts',[]) if a.get('idx')==r.get('best_attempt')),{}) for r in records]
        rows.append(dict(condition=condition,framework=jobs[0]['framework'],model_id=jobs[0]['model_id'],
            task_seconds=1200,verification_after_tests=False,n=2,recorded=sum(bool(r) for r in records),
            attempted=sum(bool(r.get('attempts')) for r in records),first_solved=sum(bool(r.get('first_try')) for r in records),
            solved=sum(bool(r.get('solved')) for r in records),fully_verified=sum(bool(r.get('fully_verified')) for r in records),
            generated=sum(any(a.get('code') for a in r.get('attempts',[])) for r in records),
            repaired=sum(bool(r.get('solved') and not r.get('first_try')) for r in records),
            two_attempts=sum(len(r.get('attempts',[]))>=2 for r in records),calls=len(attempts),
            mc_executed=sum(bool(a.get('judge',{}).get('model_check',{}).get('executed')) for a in attempts),
            incomplete=sum(a.get('provider_error','').startswith('Generation incomplete/empty:') for a in attempts),
            tests_passed=sum(a.get('tests_passed',0) for a in best),tests_total=sum(case_counts[j['pid']] for j in jobs)))
    ledger=load(cfg['budget_ledger_path']);before=load(root/'ledger_before_study.json')
    preserved=ledger.get('events',[])[:plan['initial_event_count']]==before.get('events') and ledger.get('recoveries',[])==before.get('recoveries',[])
    return dict(label='R9 第三阶段四组准备性实验',state=load(root/'study_state.json').get('state','prepared'),rows=rows,
        recorded=sum(r['recorded'] for r in rows),planned=8,source_sha256=plan['source_sha256'],
        all_original_events_preserved=preserved,total_accounted_cny=ledger.get('spent_cny'),
        study_increment_cny=round(ledger.get('spent_cny',plan['initial_spent_cny'])-plan['initial_spent_cny'],6),
        diagnostic_increment_cny=round(ledger.get('spent_cny',34.011998)-34.011998,6),
        original_diagnostic_ceiling_cny=44.011998,study_cumulative_ceiling_cny=plan['cumulative_ceiling_cny'],
        halted=ledger.get('halted'),unknown_reserved_cny=sum(e['reserved_cny'] for e in ledger.get('events',[]) if e.get('status')=='reserved'),
        new_events=len(ledger.get('events',[]))-plan['initial_event_count'],full_r9_started=False,updated_at=stamp())


def write_report(cfg,plan):
    root=Path(cfg['campaign_root']);summary=collect(cfg,plan);atomic_json(root/'study_summary.json',summary)
    state=load(root/'study_state.json')
    lines=['# R9 第三阶段四组准备性实验','','状态：'+summary['state']+'；已保存 '+str(summary['recorded'])+'/8 题次。',
        '更新时间：'+stamp(),'','两道固定代表题、两模型与两框架，最多初始生成加一次修复；单题1200秒、LTL最多30秒。',
        '修复枚举支持并澄清通用复位提示后的独立小样本，不能归因于单一改动，也不替代35题正式四组结果。','',
        '|框架|模型|已尝试/2|得到代码|首轮通过|最终通过|修复新增|LTL实际执行|截断/空回复|','|---|---|---|---|---|---|---|---|---|']
    for r in summary['rows']:
        lines.append(f"|{r['framework']}|{r['model_id']}|{r['attempted']}/2|{r['generated']}|{r['first_solved']}|{r['solved']}|{r['repaired']}|{r['mc_executed']}|{r['incomplete']}|")
    lines+=['',f"本阶段新增计入 {summary['study_increment_cny']:.6f}/7.50 元；原诊断累计增量 {summary['diagnostic_increment_cny']:.6f}/10 元；共享账本 {summary['total_accounted_cny']:.6f}/75 元。",
        '保留全部原费用事件、失败与未知预留。费用为配置价格估计，包含在途预留，并非供应商实际账单。',
        '未启动全量 R9；人工工艺复核仍待刘晏铭实际确认。']
    if state.get('current_job'):lines+=['','当前题次：'+state['current_job']]
    if state.get('error'):lines+=['','停止原因：'+state['error']]
    if state.get('state')=='running':lines+=['','运行依赖本机开机联网。新故障停止，不自动补跑。']
    text='\n'.join(lines)+'\n'
    (root/'实验状态.md').write_text(text,encoding='utf-8')
    (root/'实验状态.html').write_text('<meta charset="utf-8"><meta http-equiv="refresh" content="15"><pre>'+html.escape(text)+'</pre>',encoding='utf-8')
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
    from stage3_enum_native_controls import check_enum_controls
    check_enum_controls(cfg, root)
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
    print(json.dumps(dict(prepared=True, jobs=8, maximum_requests=16,
                         worst_reservation_cny=plan['worst_reservation_cny'], model_requests=0)), flush=True)


def published_head():
    repo = ROOT.parent
    if subprocess.check_output(['git', 'branch', '--show-current'], cwd=repo, text=True).strip() != 'main':
        raise RuntimeError('Study must start from the published main branch')
    scope = [ROOT.name + '/' + p for p in ('stbench', 'scripts', 'tests', 'datasets', 'config.r9_stage3.json')]
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
    enum_proof = load(root / 'enum_native_controls.json')
    if (enum_proof.get('passed') is not True or enum_proof.get('source_sha256') != digest() or
            enum_proof.get('platform_identity') != CodesysBackend(cfg).identity()):
        raise RuntimeError('Current real enum controls are required')
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
                    entry='r9_four_group_readiness.py', source_sha256=digest()))
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
                spec = next(m for m in cfg['models'] if m['id'] == job['model_id'])
                transport = MeteredProvider(spec, budget, max_tokens=16384, protocol=spec['generation_protocol'], timeout=420)
                sent = guarded_capture(transport, budget, plan, job, pending, folder)
                provider = transport
                if job['framework'] == 'codex':
                    gateway = stack.enter_context(ResponsesGateway(provider=transport, model=transport.model))
                    provider = CodexProvider(gateway, model=transport.model,
                        work_root=Path(cfg['platform_root']) / 'builds/codex_r9_stage3', timeout=450)
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

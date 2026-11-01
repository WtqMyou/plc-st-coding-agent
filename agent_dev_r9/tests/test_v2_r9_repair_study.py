"""Repair study safety and actual factor differences, with no paid model calls."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import r9_repair_study as study
import sync_r9_repair_study as sync
import test_v2_request_windows as windows
from stbench.campaign import configuration, digest
from stbench.evaluation import atomic_json, evaluate, StageResult
from stbench.harness.engine import Solver, solve_problem
from stbench.providers.base import ProviderError
from stbench.transport import MeteredProvider


class RepairStudy(unittest.TestCase):
    def test_complete_factorial_and_counterbalanced_task_order(self):
        jobs = study.make_jobs()
        self.assertEqual(len(jobs), 16)
        self.assertEqual(len({j['job_id'] for j in jobs}), 16)
        for pid in study.PIDS:
            self.assertEqual({(j['framework'], j['task_seconds'], j['verification_after_tests'])
                              for j in jobs if j['pid'] == pid},
                             {(fw, seconds, gate) for fw in ('custom', 'codex')
                              for seconds in (600, 1200) for gate in (False, True)})
        self.assertEqual([j['condition'] for j in jobs[:8]], [j['condition'] for j in jobs[8:]][::-1])

    def test_worst_case_all_repairs_fit_without_resetting_original_cap(self):
        cfg = configuration(str(study.CONFIG))
        origin = json.loads((ROOT / 'ORIGIN_R8.json').read_text(encoding='utf-8'))
        with tempfile.TemporaryDirectory() as directory:
            cfg['platform_root'] = directory
            cfg['budget_ledger_path'] = str(Path(directory) / 'evidence/dmxapi_budget_75.json')
            state = dict(version=3, limit_cny=75, spent_cny=35.009277, halted='', events=[dict(status='reserved')])
            atomic_json(Path(cfg['budget_ledger_path']), state)
            proof = dict(passed=True, source_sha256=digest(), request_window_seconds=450,
                         deadline_checks={k: True for k in ('cli_tree_deadline', 'upstream_failure_aborts_cli',
                         'single_upstream_request', 'full_request_window', 'request_window_keeps_best',
                         'genuine_timeout_keeps_halt')})
            plan = study.build_plan(cfg, state, origin, proof)
            self.assertLess(plan['worst_reservation_cny'], 8)
            self.assertEqual(plan['maximum_requests'], 32)
            self.assertEqual(plan['cumulative_ceiling_cny'], 43.009277)
            self.assertEqual(study.study_budget(cfg, plan).ceiling(), 43.009277)
            with self.assertRaises(RuntimeError):
                study.build_plan(cfg, state, origin, proof | {'deadline_checks': {}})
            for key, value in [('cumulative_ceiling_cny', 75), ('study_additional_cap_cny', 10)]:
                with self.assertRaises(RuntimeError):
                    study.study_budget(cfg, plan | {key: value})

    def fixture(self, directory):
        cfg = configuration(str(study.CONFIG))
        cfg['platform_root'] = directory
        cfg['budget_ledger_path'] = str(Path(directory) / 'evidence/dmxapi_budget_75.json')
        ledger = dict(version=3, limit_cny=75, spent_cny=35.009277, halted='',
                      events=[dict(request_id='old-unknown', status='reserved', reserved_cny=.78450215)])
        atomic_json(Path(cfg['budget_ledger_path']), ledger)
        plan = dict(initial_spent_cny=35.009277, cumulative_ceiling_cny=43.009277,
                    study_additional_cap_cny=8., original_diagnostic_ceiling_cny=44.011998)
        budget = study.study_budget(cfg, plan)
        provider = MeteredProvider(cfg['models'][1], budget, max_tokens=16384, timeout=420, offline=True)
        job = dict(pid='p', job_id='condition/p', first_upper_cny=.3, repair_upper_cny=.4)
        return cfg, ledger, plan, budget, provider, job

    def test_request_guard_protects_all_future_jobs_and_limits_two_calls(self):
        with tempfile.TemporaryDirectory() as directory:
            _, _, plan, budget, provider, job = self.fixture(directory)
            pending = {job['job_id']: .7, 'other': .8}
            folder = Path(directory) / 'jobs'
            count = study.guarded_capture(provider, budget, plan, job, pending, folder)
            provider.before_send([dict(role='user', content='first')])
            self.assertAlmostEqual(budget.protected_cny, 1.2)
            provider.before_send([dict(role='user', content='repair')])
            self.assertAlmostEqual(budget.protected_cny, .8)
            with self.assertRaises(ProviderError):
                provider.before_send([dict(role='user', content='third')])
            self.assertEqual(count[0], 2)
            self.assertEqual(budget.read()['events'][0]['request_id'], 'old-unknown')
            self.assertEqual(len(budget.read()['events']), 1)  # Guards themselves never bill.

    def test_oversized_input_stops_before_receipt_or_charge(self):
        with tempfile.TemporaryDirectory() as directory:
            _, _, plan, budget, provider, job = self.fixture(directory)
            count = study.guarded_capture(provider, budget, plan, job, {job['job_id']: .7}, Path(directory))
            before = budget.path.read_bytes()
            with self.assertRaises(ProviderError):
                provider.generate([dict(role='user', content='x' * 200000)])
            self.assertEqual(count[0], 0)
            self.assertEqual(budget.path.read_bytes(), before)

    def test_duplicate_trace_is_never_reissued(self):
        with tempfile.TemporaryDirectory() as directory:
            _, _, plan, budget, provider, job = self.fixture(directory)
            folder = Path(directory) / 'jobs'
            atomic_json(folder / 'p.request_01.json', {'existing': True})
            study.guarded_capture(provider, budget, plan, job, {job['job_id']: .7}, folder)
            before = budget.path.read_bytes()
            with self.assertRaises(ProviderError):
                provider.generate([dict(role='user', content='first')])
            self.assertEqual(budget.path.read_bytes(), before)

    def test_unknown_charge_preserves_old_events_and_stops_without_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            _, old, plan, budget, provider, job = self.fixture(directory)
            calls = []
            def fail(*args):
                calls.append(1)
                raise ProviderError('Upstream RemoteDisconnected; no automatic retry')
            provider.sender = fail
            study.guarded_capture(provider, budget, plan, job, {job['job_id']: .7}, Path(directory) / 'jobs')
            with self.assertRaises(ProviderError):
                provider.generate([dict(role='user', content='first')])
            state = budget.read(allow_halted=True)
            self.assertEqual(calls, [1])
            self.assertEqual(state['events'][:1], old['events'])
            self.assertEqual(state['events'][-1]['status'], 'reserved')
            self.assertTrue(state['halted'])
            with self.assertRaises(ProviderError):
                budget.snapshot()

    def test_time_factor_changes_real_repair_opportunity_without_shortening_calls(self):
        for seconds, expected_calls in [(600, 1), (1200, 2)]:
            with self.subTest(seconds=seconds), tempfile.TemporaryDirectory() as directory:
                clock = windows.Clock()
                provider, _, calls = windows.RequestWindows().provider(directory, clock, [290, 10])
                def judge(*args):
                    return StageResult(compiles=True, tests_total=1, tests_passed=int(len(calls) == 2),
                        mc_executed=len(calls) == 2, mc_specs_total=int(len(calls) == 2), mc_specs_hold=int(len(calls) == 2))
                solver = Solver(provider, max_iters=2, task_seconds=seconds, request_window_seconds=450, evaluator=judge)
                with patch('stbench.harness.engine.time.monotonic', clock.monotonic):
                    record = solve_problem(windows.problem(), solver)
                self.assertEqual(calls, [420] * expected_calls)
                self.assertEqual(record.solved, seconds == 1200)

    def test_check_policy_only_defers_ltl_on_failed_functional_tests(self):
        p = windows.problem()
        source = 'FUNCTION_BLOCK FB VAR_OUTPUT out:BOOL; END_VAR out:=FALSE; END_FUNCTION_BLOCK'
        for defer in (False, True):
            result = evaluate(source, p, model_check=True, verification_after_tests=defer, timeout_s=3)
            self.assertEqual(result.tests_passed, 0)
            self.assertEqual(result.mc_executed, not defer)

    def test_secrets_are_redacted_in_trace_and_rejected_before_git(self):
        secret = 'sk-' + 'a' * 40
        with patch.dict('os.environ', DMXAPI_API_KEY=secret):
            self.assertNotIn(secret, study.sanitize('model content ' + secret))
            with self.assertRaises(RuntimeError):
                sync.assert_publishable(secret.encode(), 'response.json')
        sync.assert_publishable(b'{"api_key_env":"DMXAPI_API_KEY"}', 'config.json')

    def test_public_mirror_excludes_ledger_credentials_and_process_locks(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            source = repo / 'external'
            atomic_json(source / 'study_plan.json', {'ok': True})
            atomic_json(source / 'jobs/arm/p.json', {'attempts': []})
            for name in ('ledger_before_study.json', 'active_run.json', 'credential_check.json'):
                atomic_json(source / name, {'private': True})
            with patch.object(sync, 'REPO', repo):
                self.assertEqual(sync.publish_files(source, Path('published')), 2)
            names = [p.name for p in (repo / 'published').rglob('*') if p.is_file()]
            self.assertNotIn('ledger_before_study.json', names)
            self.assertNotIn('active_run.json', names)
            self.assertNotIn('credential_check.json', names)
            manifest = json.loads((repo / 'published/publication_manifest.json').read_text(encoding='utf-8'))
            self.assertEqual(len(manifest['files']), 2)

    def test_git_sync_does_not_commit_other_staged_work(self):
        commands = []
        def git(args):
            commands.append(args)
            if args == ['branch', '--show-current']: return 'main'
            if args[:2] == ['remote', 'get-url']: return 'https://github.com/WtqMyou/plc-st-coding-agent.git'
            if args == ['rev-parse', 'HEAD']: return 'expected'
            if args == ['diff', '--cached', '--name-only']: return 'user-file.txt'
            return ''
        with patch.object(sync, 'run_git', git), self.assertRaises(RuntimeError):
            sync.sync_git({}, 'expected')
        self.assertFalse(any(c[0] in ('add', 'commit', 'push') for c in commands))

    def test_missing_and_failed_jobs_keep_the_original_denominators(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg, old, plan, _, _, _ = self.fixture(directory)
            root = Path(directory) / 'study'
            cfg['campaign_root'] = str(root)
            atomic_json(root / 'ledger_before_study.json', old)
            atomic_json(root / 'study_state.json', {'state': 'running'})
            jobs = study.make_jobs()
            plan.update(jobs=jobs, source_sha256=digest(), initial_event_count=1)
            job = jobs[0]
            atomic_json(root / 'jobs' / job['condition'] / (job['pid'] + '.json'),
                        dict(attempts=[dict(provider_error='network failure')], solved=False,
                             first_try=False, stop_reason='provider_error'))
            summary = study.collect(cfg, plan)
            self.assertEqual(summary['recorded'], 1)
            self.assertEqual(summary['planned'], 16)
            self.assertTrue(summary['all_original_events_preserved'])
            self.assertTrue(all(r['n'] == 2 and r['tests_total'] > 0 for r in summary['rows']))
            self.assertFalse(any(c['complete'] for c in summary['contrasts']))
            self.assertEqual(summary['unknown_reserved_cny'], .78450215)


if __name__ == '__main__':
    unittest.main()

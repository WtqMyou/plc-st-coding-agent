"""Paid requests must fit their full configured window inside the remaining task time."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from stbench.billing import CampaignBudget
from stbench.evaluation import StageResult
from stbench.harness.engine import Solver, solve_problem, summarize
from stbench.schema import Problem
from stbench.transport import MeteredProvider, RequestDeadline


class Clock:
    now = 0.

    def advance(self, seconds):
        self.now += seconds

    def monotonic(self):
        return self.now


def problem():
    return Problem.from_dict(dict(pid='request-window', source='selfmade', title='window',
        difficulty='easy', requirements='output true',
        variables=[dict(name='out', data_type='BOOL', direction='output')],
        test_cases=[dict(tc_id='case', inputs={}, expected={'out': True})]))


def violated(*args, **kwargs):
    return StageResult(compiles=True, tests_total=1, tests_passed=1,
        mc_executed=True, mc_specs_total=1, mc_specs_violated=1,
        platform_results={'codesys': {'status': 'passed'}})


class RequestWindows(unittest.TestCase):
    def provider(self, directory, clock, durations):
        budget = CampaignBudget(Path(directory) / 'ledger.json', 'development')
        calls = []

        def sender(url, payload, key, timeout):
            index = len(calls)
            calls.append(timeout)
            clock.advance(durations[index])
            return dict(model='window-fixture', usage=dict(prompt_tokens=10, completion_tokens=20),
                choices=[dict(finish_reason='stop', message=dict(content=
                    'FUNCTION_BLOCK FB VAR_OUTPUT out:BOOL; END_VAR '
                    f'out:=TRUE; (* candidate {index} *) END_FUNCTION_BLOCK'))])

        provider = MeteredProvider(dict(model='window-fixture', base_url='https://example.invalid/v1',
            api_key_env='UNUSED', input_cny_per_million=1, output_cny_per_million=2),
            budget, timeout=420, offline=True, sender=sender)
        return provider, budget, calls

    def solver(self, provider, **kwargs):
        return Solver(provider, max_iters=5, task_seconds=600, request_window_seconds=450,
                      evaluator=violated, **kwargs)

    def test_observed_latency_sequence_stops_before_a_short_paid_request(self):
        with tempfile.TemporaryDirectory() as directory:
            clock = Clock()
            provider, budget, calls = self.provider(directory, clock, [127.625, 238.968, 74.906, 145.188, 13.297])
            with patch('stbench.harness.engine.time.monotonic', clock.monotonic):
                record = solve_problem(problem(), self.solver(provider))
            self.assertEqual(calls, [420, 420])
            self.assertEqual(record.stop_reason, 'insufficient_request_window')
            self.assertEqual(record.error, '')
            self.assertEqual(len(record.attempts), 2)
            self.assertTrue(record.solved)
            self.assertEqual(record.best.idx, 0)
            state = budget.snapshot()
            self.assertEqual(len(state['events']), 2)
            self.assertTrue(all(e['status'] == 'settled' for e in state['events']))
            self.assertFalse(state['halted'])
            self.assertEqual(summarize([record])['request_window_stopped_tasks'], 1)

    def test_thirteen_seconds_remaining_never_creates_a_request_or_charge(self):
        with tempfile.TemporaryDirectory() as directory:
            clock = Clock()
            provider, budget, calls = self.provider(directory, clock, [])
            with patch('stbench.harness.engine.time.monotonic', clock.monotonic):
                record = solve_problem(problem(), self.solver(provider), active_elapsed_before=586.718)
            self.assertEqual(calls, [])
            self.assertFalse(budget.path.exists())
            self.assertEqual(record.attempts, [])
            self.assertEqual(record.stop_reason, 'insufficient_request_window')
            self.assertEqual(summarize([record])['tests_total'], 1)

    def test_a_full_remaining_window_allows_a_real_repair(self):
        with tempfile.TemporaryDirectory() as directory:
            clock = Clock()
            provider, _, calls = self.provider(directory, clock, [150, 1])
            solver = self.solver(provider)

            def evaluate(*args):
                result = violated()
                if len(calls) == 2:
                    result.mc_specs_violated = 0
                    result.mc_specs_hold = 1
                return result

            solver.evaluator = evaluate
            with patch('stbench.harness.engine.time.monotonic', clock.monotonic):
                record = solve_problem(problem(), solver)
            self.assertEqual(calls, [420, 420])
            self.assertEqual(record.stop_reason, 'verified')

    def test_prompt_preparation_time_is_checked_before_sending(self):
        with tempfile.TemporaryDirectory() as directory:
            clock = Clock()
            provider, budget, calls = self.provider(directory, clock, [])

            def slow_prompt(*args, **kwargs):
                clock.advance(150.1)
                return 'task'

            with patch('stbench.harness.engine.time.monotonic', clock.monotonic), \
                 patch('stbench.harness.engine.build_task_prompt', side_effect=slow_prompt):
                record = solve_problem(problem(), self.solver(provider))
            self.assertEqual(calls, [])
            self.assertFalse(budget.path.exists())
            self.assertEqual(record.stop_reason, 'insufficient_request_window')

    def test_resume_counts_platform_time_and_preserves_the_best_candidate(self):
        with tempfile.TemporaryDirectory() as directory:
            clock = Clock()
            provider, budget, calls = self.provider(directory, clock, [151])
            solver = self.solver(provider)
            folder = Path(directory) / 'records'
            with patch('stbench.harness.engine.time.monotonic', clock.monotonic):
                record = solve_problem(problem(), solver, log_dir=folder)
                record.stop_reason = 'repair_budget_deferred'
                record.save(folder / 'request-window.json')
                before = budget.path.read_bytes()
                resumed = solve_problem(problem(), solver, log_dir=folder, resume=True, active_elapsed_before=200)
            self.assertEqual(calls, [420])
            self.assertEqual(resumed.best.code, record.best.code)
            self.assertEqual(resumed.stop_reason, 'insufficient_request_window')
            self.assertEqual(budget.path.read_bytes(), before)

    def test_a_genuine_upstream_timeout_keeps_the_unknown_reservation_and_halt(self):
        with tempfile.TemporaryDirectory() as directory:
            clock = Clock()
            provider, budget, _ = self.provider(directory, clock, [])

            def timeout(*args):
                clock.advance(420)
                raise RequestDeadline('Upstream wall deadline exceeded; no automatic retry')

            provider.sender = timeout
            with patch('stbench.harness.engine.time.monotonic', clock.monotonic):
                record = solve_problem(problem(), self.solver(provider))
            self.assertEqual(record.stop_reason, 'provider_error')
            self.assertEqual(len(record.attempts), 1)
            state = json.loads(budget.path.read_text(encoding='utf-8'))
            self.assertEqual(state['events'][0]['status'], 'reserved')
            self.assertEqual(state['events'][0]['request']['timeout_seconds'], 420)
            self.assertTrue(state['halted'])

    def test_invalid_request_windows_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            provider, _, _ = self.provider(directory, Clock(), [])
            for value in (-1, float('nan'), float('inf'), True, 419):
                with self.subTest(value=value), self.assertRaises(ValueError):
                    Solver(provider, request_window_seconds=value)

    def test_resume_rejects_a_different_request_window(self):
        with tempfile.TemporaryDirectory() as directory:
            clock = Clock()
            provider, _, _ = self.provider(directory, clock, [151])
            folder = Path(directory) / 'records'
            with patch('stbench.harness.engine.time.monotonic', clock.monotonic):
                solve_problem(problem(), self.solver(provider), log_dir=folder)
                changed = Solver(provider, max_iters=5, task_seconds=600, request_window_seconds=460, evaluator=violated)
                with self.assertRaisesRegex(ValueError, 'Resume rejected'):
                    solve_problem(problem(), changed, log_dir=folder, resume=True)


if __name__ == '__main__':
    unittest.main()

"""A diagnosed timeout can be retained while only the remaining jobs proceed."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import resume_final_after_timeout as recovery
from request_accounting import accounting_record
from stbench.campaign import configuration
from stbench.evaluation import atomic_json
from stbench.harness.engine import Attempt, RunRecord, solve_problem
from stbench.transport import RequestDeadline
import test_v2_request_windows as windows


class Accounting(unittest.TestCase):
    def test_pause_does_not_inflate_requests_or_unknown_cost_and_raw_evidence_survives(self):
        first = Attempt(0, 'candidate', True, 1, 1, actual_model='model', prompt_tokens=3, cost_cny=.01)
        pause = Attempt(1, '', False, 0, 1,
                        provider_error='Campaign halted: Paused by user for laptop relocation')
        record = RunRecord('p', 'model', 'provider', 'iterative', 5, attempts=[first, pause])
        raw = record.to_dict()
        filtered, controls = accounting_record(record)
        self.assertEqual(controls, 1)
        self.assertEqual(filtered.attempts, [first])
        self.assertEqual(filtered.best, first)
        self.assertEqual(filtered.total_tokens, record.total_tokens)
        self.assertEqual(record.to_dict(), raw)

    def test_genuine_timeout_is_still_a_failed_request_with_unknown_cost(self):
        attempt = Attempt(0, '', False, 0, 1, provider_error=recovery.ERROR, latency_s=420)
        record = RunRecord('p', 'model', 'provider', 'iterative', 5, attempts=[attempt])
        filtered, controls = accounting_record(record)
        self.assertEqual(controls, 0)
        self.assertEqual(len(filtered.attempts), 1)
        self.assertTrue(filtered.attempts[0].provider_error)

    def test_a_pause_entry_with_any_receipt_or_generated_code_is_not_hidden(self):
        for kwargs in [dict(actual_model='model'), dict(prompt_tokens=1), dict(completion_tokens=1),
                       dict(cost_cny=.001), dict(code='generated')]:
            fields = dict(idx=0, code='', compiles=False, tests_passed=0, tests_total=1,
                          provider_error='Campaign halted: Paused by user for laptop relocation')
            fields.update(kwargs)
            record = RunRecord('p', 'model', 'provider', 'iterative', 5, attempts=[Attempt(**fields)])
            with self.subTest(kwargs=kwargs):
                self.assertEqual(accounting_record(record)[1], 0)

    def test_a_pause_only_task_remains_unattempted_in_the_full_denominator(self):
        record = RunRecord('p', 'model', 'provider', 'iterative', 5, tests_total=7, attempts=[
            Attempt(0, '', False, 0, 7, provider_error='Campaign halted: Paused by user for laptop relocation')])
        filtered, _ = accounting_record(record)
        self.assertFalse(filtered.attempts)
        self.assertFalse(filtered.solved)
        self.assertEqual(filtered.tests_total, 7)


class TimeoutContinuation(unittest.TestCase):
    def inputs(self):
        cfg = configuration('')
        model = cfg['models'][1]['model']
        state = dict(version=3, limit_cny=75, spent_cny=12.5,
            halted='Unconfirmed upstream result; reservation retained', events=[
                dict(request_id='older', status='reserved', reserved_cny=.4),
                dict(request_id='current', status='reserved', reserved_cny=.17, phase='final', created_at=1000.,
                     request=dict(model=model, protocol='chat', timeout_seconds=420, max_output_tokens=16384))],
            halt_details=dict(category='request_timeout', model=model, protocol='chat', event_index=1))
        record = dict(pid='task', model=model, provider='codex-cli', experiment_kind='live',
            stop_reason='provider_error', error=recovery.ERROR, request_window_seconds=450,
            started_at=996., finished_at=1420.3, total_latency_s=423.8,
            attempts=[dict(code='', actual_model='', prompt_tokens=0, completion_tokens=0, cost_cny=0.,
                           provider_error=recovery.ERROR, latency_s=423.8)])
        timing = dict(active_wall_seconds=424.3)
        plan = dict(action='explicit_continue_remaining_after_full_timeout', ledger_state_sha256=recovery.state_hash(state),
                    event_count=2, spent_cny=12.5, request_id='current')
        return cfg, state, record, timing, plan

    def test_exact_full_timeout_is_eligible_without_a_refund_or_retry(self):
        cfg, state, record, timing, plan = self.inputs()
        recovery.validate_timeout(state, record, timing, cfg, plan)

    def test_a_new_event_or_changed_spending_invalidates_the_old_plan(self):
        cfg, state, record, timing, plan = self.inputs()
        for change in [dict(spent_cny=12.6), dict(events=state['events'] + [state['events'][-1]])]:
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                recovery.validate_timeout(state | change, record, timing, cfg, plan)

    def test_changed_category_phase_settlement_or_timeout_cannot_use_this_recovery(self):
        cfg, state, record, timing, plan = self.inputs()
        for change in ['category', 'phase', 'settlement', 'short_timeout', 'reused']:
            changed = copy.deepcopy(state)
            if change == 'category': changed['halt_details']['category'] = 'model_identity'
            if change == 'phase': changed['events'][-1]['phase'] = 'development'
            if change == 'settlement': changed['events'][-1]['status'] = 'settled'
            if change == 'short_timeout': changed['events'][-1]['request']['timeout_seconds'] = 13
            if change == 'reused': changed['recoveries'] = [dict(request_id='current')]
            updated = plan | dict(ledger_state_sha256=recovery.state_hash(changed))
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                recovery.validate_timeout(changed, record, timing, cfg, updated)

    def test_known_receipts_multiple_attempts_or_time_for_a_retry_are_rejected(self):
        cfg, state, record, timing, plan = self.inputs()
        variants = [dict(attempts=[record['attempts'][0] | dict(actual_model=record['model'])]),
                    dict(attempts=record['attempts'] * 2), dict(total_latency_s=100., finished_at=1100.)]
        for change in variants:
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                recovery.validate_timeout(state, record | change, dict(active_wall_seconds=100.), cfg, plan)

    def test_release_keeps_the_complete_ledger_and_cannot_be_applied_twice(self):
        cfg, state, record, timing, plan = self.inputs()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            ledger = root / 'evidence' / 'dmxapi_budget_75.json'
            cfg.update(platform_root=str(root), campaign_root=str(root), budget_ledger_path=str(ledger))
            atomic_json(ledger, state)
            original = ledger.read_bytes()
            history = root / 'history'
            history.mkdir()
            with patch.object(recovery, 'registered_process_alive', return_value=False):
                receipt = recovery.release_timeout(cfg, plan, record, timing, history, dict(run_id='new'))
                after = json.loads(ledger.read_bytes())
                self.assertEqual(after['events'], state['events'])
                self.assertEqual(after['spent_cny'], state['spent_cny'])
                self.assertEqual((history / 'ledger_before_resume.json').read_bytes(), original)
                self.assertAlmostEqual(receipt['all_unknown_reservations_retained'], .57)
                self.assertEqual(receipt['current_reservation_retained'], .17)
                self.assertFalse(after['halted'])
                with self.assertRaises(RuntimeError):
                    recovery.release_timeout(cfg, plan, record, timing, history, dict(run_id='again'))

    def test_a_live_runner_blocks_release_without_changing_the_ledger(self):
        cfg, state, record, timing, plan = self.inputs()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            ledger = root / 'evidence' / 'dmxapi_budget_75.json'
            cfg.update(platform_root=str(root), campaign_root=str(root), budget_ledger_path=str(ledger))
            atomic_json(ledger, state)
            original = ledger.read_bytes()
            with patch.object(recovery, 'registered_process_alive', return_value=True), self.assertRaises(RuntimeError):
                recovery.release_timeout(cfg, plan, record, timing, root, dict(run_id='duplicate'))
            self.assertEqual(ledger.read_bytes(), original)

    def test_saved_timeout_uses_original_deadline_and_issues_no_second_request(self):
        with tempfile.TemporaryDirectory() as directory:
            helper = windows.RequestWindows()
            clock = windows.Clock()
            provider, budget, calls = helper.provider(directory, clock, [])
            sent = []
            def timeout(*args):
                sent.append(True)
                clock.advance(420)
                raise RequestDeadline(recovery.ERROR)
            provider.sender = timeout
            solver = helper.solver(provider)
            folder = Path(directory) / 'records'
            with patch('stbench.harness.engine.time.monotonic', clock.monotonic):
                original = solve_problem(windows.problem(), solver, log_dir=folder)
                ledger_before = budget.path.read_bytes()
                resumed = solve_problem(windows.problem(), solver, log_dir=folder, resume=True, active_elapsed_before=424.3)
            self.assertEqual(len(sent), 1)
            self.assertEqual(resumed.attempts, original.attempts)
            self.assertEqual(resumed.stop_reason, 'insufficient_request_window')
            self.assertEqual(budget.path.read_bytes(), ledger_before)
            self.assertEqual(calls, [])


if __name__ == '__main__':
    unittest.main()

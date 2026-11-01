"""A user resume must preserve charges and the frozen development selection."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import resume_user_paused_campaign as resume
from campaign_status import write_status
from stbench.evaluation import atomic_json


class UserPauseResume(unittest.TestCase):
    def inputs(self):
        before = dict(version=3, limit_cny=75, spent_cny=12.5, halted='', events=[
            dict(request_id='older-unknown', status='reserved', reserved_cny=.4),
            dict(request_id='settled', status='settled', reserved_cny=.5, accounted_cny=.2)])
        state = copy.deepcopy(before)
        state.update(halted='Paused by user for laptop relocation',
                     halt_details=dict(category='user_pause', pause_id='pause123'))
        pause = dict(state='paused', pause_id='pause123', resume_stage='final', source_sha256='source',
                     runner_stopped=True, collector_stopped=True, spent_cny=12.5, event_count=2,
                     last_request_id='settled', last_event_status='settled')
        return before, state, pause

    def test_exact_settled_pause_accepts_retained_historical_unknown_cost(self):
        before, state, pause = self.inputs()
        resume.validate_pause(state, pause, before, 'source')
        self.assertEqual(state['events'][0]['status'], 'reserved')

    def test_other_halts_changed_spending_and_stale_events_are_rejected(self):
        before, state, pause = self.inputs()
        variants = [dict(halted='Unconfirmed upstream result; reservation retained'),
                    dict(spent_cny=12.6), dict(halt_details=dict(category='request_timeout', pause_id='pause123')),
                    dict(events=state['events'][:-1]),
                    dict(recoveries=[dict(pause_id='pause123')])]
        for change in variants:
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                resume.validate_pause(state | change, pause, before, 'source')

    def test_edited_history_or_an_unsettled_last_request_cannot_resume(self):
        before, state, pause = self.inputs()
        for index, key, value in [(0, 'reserved_cny', .1), (1, 'status', 'reserved')]:
            changed = copy.deepcopy(state)
            changed['events'][index][key] = value
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                resume.validate_pause(changed, pause, before, 'source')

    def test_changed_source_or_unconfirmed_process_shutdown_cannot_resume(self):
        before, state, pause = self.inputs()
        for change in [dict(source_sha256='new'), dict(runner_stopped=False), dict(collector_stopped=False)]:
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                resume.validate_pause(state, pause | change, before, 'source')

    def test_release_backs_up_and_keeps_all_money_and_events(self):
        before, state, pause = self.inputs()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            ledger, backup = root / 'evidence' / 'dmxapi_budget_75.json', root / 'before_pause.json'
            atomic_json(ledger, state)
            raw = ledger.read_bytes()
            atomic_json(backup, before)
            pause['backup'] = str(backup)
            history = root / 'history'
            history.mkdir()
            cfg = dict(campaign_root=str(root), platform_root=str(root), budget_ledger_path=str(ledger),
                       budget_cny=75, phase_limits=dict(preflight=8, development=20, final=65, retest=75))
            with patch.object(resume.campaign, 'digest', return_value='source'), \
                    patch.object(resume, 'registered_process_alive', return_value=False):
                receipt = resume.release_pause(cfg, pause, history, dict(run_id='run123'))
                after = json.loads(ledger.read_bytes())
                self.assertEqual(after['spent_cny'], state['spent_cny'])
                self.assertEqual(after['events'], state['events'])
                self.assertEqual((history / 'ledger_before_resume.json').read_bytes(), raw)
                self.assertEqual(receipt['unknown_reservations_retained'], .4)
                self.assertEqual(after['halted'], '')
                with self.assertRaises(RuntimeError):
                    resume.release_pause(cfg, pause, history, dict(run_id='again'))

    def test_a_live_registered_process_blocks_release_without_touching_ledger(self):
        before, state, pause = self.inputs()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            ledger, backup = root / 'evidence' / 'dmxapi_budget_75.json', root / 'backup.json'
            atomic_json(ledger, state)
            atomic_json(backup, before)
            pause['backup'] = str(backup)
            cfg = dict(campaign_root=str(root), platform_root=str(root), budget_ledger_path=str(ledger), budget_cny=75,
                       phase_limits=dict(preflight=8, development=20, final=65, retest=75))
            original = ledger.read_bytes()
            with patch.object(resume.campaign, 'digest', return_value='source'), \
                    patch.object(resume, 'registered_process_alive', return_value=True), \
                    self.assertRaises(RuntimeError):
                resume.release_pause(cfg, pause, root, dict(run_id='duplicate'))
            self.assertEqual(ledger.read_bytes(), original)

    def test_continuation_skips_development_and_uses_frozen_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            selected = dict(campaign_root=str(root), strategy=dict(include_ltl=True), models=[dict(id='a'), dict(id='b')])
            rows = [dict(framework=fw, model_id=mid, n=35, attempted=35, generated=34, solve_rate=.5)
                    for fw, mid in resume.campaign.group_order(selected)]
            atomic_json(root / 'final' / 'summary.json', rows)
            with patch.object(resume.campaign, 'main') as run, patch.object(resume.campaign, 'budget_for') as budget:
                budget.return_value.snapshot.return_value = dict(spent_cny=20, halted='')
                resume.execute_remaining(selected, dict(pause_id='pause123'), root)
            run.assert_called_once_with(['final', '--live', '--config', str(root / 'selected_configuration.json')])
            completion = json.loads((root / 'campaign_completion.json').read_bytes())
            self.assertEqual(completion['final_conditions'], 4)
            self.assertFalse(completion['full_generation_coverage'])

    def test_partial_formal_coverage_is_not_marked_complete(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            selected = dict(campaign_root=str(root), models=[dict(id='a'), dict(id='b')])
            rows = [dict(framework=fw, model_id=mid, n=35, attempted=10, generated=10)
                    for fw, mid in resume.campaign.group_order(selected)]
            atomic_json(root / 'final' / 'summary.json', rows)
            with patch.object(resume.campaign, 'main'), self.assertRaises(RuntimeError):
                resume.execute_remaining(selected, dict(pause_id='pause123'), root)
            self.assertFalse((root / 'campaign_completion.json').exists())

    def test_new_running_markers_display_running_instead_of_old_pause(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            atomic_json(root / 'active_run.json', dict(state='running'))
            atomic_json(root / 'finish_status.json', dict(state='running'))
            atomic_json(root / 'runner_exit.json', dict(state='running'))
            with patch('campaign_status.registered_process_alive', return_value=True):
                write_status(root, dict(budget_ledger_path=str(root / 'missing.json')))
            self.assertTrue((root / '实验状态.txt').read_text(encoding='utf-8').startswith('实验正在运行'))


if __name__ == '__main__':
    unittest.main()

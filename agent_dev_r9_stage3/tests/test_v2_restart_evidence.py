"""Restart evidence must preserve raw pilot records and every unknown reservation."""
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from pilot_provenance import accepted_sources
import recover_request_window as recovery
from stbench.billing import CampaignBudget
from stbench.campaign import configuration, digest


def freeze(version):
    return dict(version=3, judge_sha256=str(version), config={'same': True}, profile='same',
                routes={'model': 'chat'}, tasks=[{'pid': 'one'}],
                files={'stbench/harness/engine.py': str(version), 'stbench/evaluation.py': 'judge',
                       'stbench/harness/prompts.py': 'prompt', 'datasets/one.json': 'data'})


def reuse(old, current, previous=None):
    return dict(source_freeze=old, current_source_sha256=current['judge_sha256'],
                changed_files=['stbench/harness/engine.py'], copied_files=[], previous_reuse=previous)


class PilotProvenance(unittest.TestCase):
    def test_multiple_compatible_generations_keep_every_source_hash(self):
        one, two, three = [freeze(i) for i in range(3)]
        proof = reuse(two, three, reuse(one, two))
        self.assertEqual(accepted_sources(three, proof), {'0', '1', '2'})

    def test_private_judge_data_and_prompt_changes_are_rejected(self):
        for path in ('stbench/evaluation.py', 'datasets/one.json', 'stbench/harness/prompts.py'):
            old, current = freeze(0), freeze(1)
            current['files'][path] = 'changed'
            with self.subTest(path=path), self.assertRaises(RuntimeError):
                accepted_sources(current, reuse(old, current))

    def test_config_route_and_task_changes_are_rejected(self):
        for key in ('config', 'routes', 'tasks', 'profile'):
            old, current = freeze(0), freeze(1)
            current[key] = 'changed'
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                accepted_sources(current, reuse(old, current))

    def test_an_incompatible_older_link_cannot_be_hidden_by_a_new_link(self):
        one, two, three = [freeze(i) for i in range(3)]
        one['files']['stbench/evaluation.py'] = 'older incompatible judge'
        with self.assertRaises(RuntimeError):
            accepted_sources(three, reuse(two, three, reuse(one, two)))

    def test_changed_copied_record_bytes_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            record = root / 'pilot/group/a.json'
            record.parent.mkdir(parents=True)
            record.write_bytes(b'original')
            old, current = freeze(0), freeze(1)
            proof = reuse(old, current)
            proof['copied_files'] = [dict(path='pilot/group/a.json', sha256=hashlib.sha256(b'original').hexdigest())]
            self.assertEqual(accepted_sources(current, proof, root=root), {'0', '1'})
            record.write_bytes(b'modified')
            with self.assertRaises(RuntimeError):
                accepted_sources(current, proof, root=root)

    def test_copied_file_paths_cannot_escape_the_campaign(self):
        old, current = freeze(0), freeze(1)
        proof = reuse(old, current)
        proof['copied_files'] = [dict(path='../outside.json', sha256='unused')]
        with tempfile.TemporaryDirectory() as directory, self.assertRaises(RuntimeError):
            accepted_sources(current, proof, root=directory)


class TaskTailRecovery(unittest.TestCase):
    def inputs(self):
        cfg = configuration('')
        model = cfg['models'][1]['model']
        error = 'Upstream wall deadline exceeded; no automatic retry'
        record = dict(model=model, experiment_kind='live', stop_reason='provider_error', error=error,
            started_at=1000, finished_at=1600, attempts=[dict(latency_s=586.718),
            dict(latency_s=13.282, code='', actual_model='', prompt_tokens=0, completion_tokens=0, provider_error=error)])
        event = dict(status='reserved', phase='development', created_at=1586.718,
                     request=dict(model=model, timeout_seconds=13.282))
        details = dict(category='request_timeout', model=model)
        proof = dict(passed=True, source_sha256=digest(), request_window_seconds=450,
                     deadline_checks={k: True for k in ('full_request_window', 'request_window_keeps_best',
                                                         'genuine_timeout_keeps_halt')})
        return record, event, details, cfg, proof

    def test_diagnosed_task_tail_is_eligible(self):
        recovery.validate_failure(*self.inputs())

    def test_full_timeout_and_non_tail_failures_are_rejected(self):
        for change in ('full', 'not-tail', 'different-model'):
            record, event, details, cfg, proof = self.inputs()
            if change == 'full':
                event['request']['timeout_seconds'] = 420
            elif change == 'not-tail':
                record['attempts'][0]['latency_s'] = 300
            else:
                event['request']['model'] = 'other'
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                recovery.validate_failure(record, event, details, cfg, proof)

    def test_missing_or_stale_validation_is_rejected(self):
        for change in ('stale', 'missing-guard'):
            args = self.inputs()
            if change == 'stale':
                args[-1]['source_sha256'] = 'old'
            else:
                args[-1]['deadline_checks']['full_request_window'] = False
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                recovery.validate_failure(*args)

    def test_a_returned_receipt_is_not_an_unknown_task_tail(self):
        args = self.inputs()
        args[0]['attempts'][-1]['actual_model'] = args[0]['model']
        with self.assertRaises(RuntimeError):
            recovery.validate_failure(*args)

    def test_recovery_keeps_all_events_charges_and_the_original_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            record, _, details, cfg, proof = self.inputs()
            cfg = copy.deepcopy(cfg)
            cfg.update(platform_root=directory, campaign_root=str(Path(directory) / 'run'),
                       budget_ledger_path=str(Path(directory) / 'evidence/dmxapi_budget_75.json'))
            budget = CampaignBudget(cfg['budget_ledger_path'], 'development')
            budget.reserve(.3)  # older unknown reservation must also survive
            index = budget.reserve(.128472, request=dict(model=record['model'], timeout_seconds=13.282))
            event = budget.snapshot()['events'][index]
            record.update(started_at=event['created_at'] - 586.718, finished_at=event['created_at'] + 13.282)
            budget.halt('Unconfirmed upstream result; reservation retained', details=dict(details, event_index=index))
            original = json.loads(budget.path.read_text())
            failure, validation = Path(directory) / 'failure.json', Path(directory) / 'validation.json'
            failure.write_text(json.dumps(record), encoding='utf-8')
            validation.write_text(json.dumps(proof), encoding='utf-8')
            arguments = ['recover', '--failure', str(failure), '--validation', str(validation)]
            with patch.object(recovery, 'configuration', return_value=cfg), patch.object(sys, 'argv', arguments), \
                 contextlib.redirect_stdout(io.StringIO()):
                recovery.main()
                with self.assertRaises(RuntimeError):
                    recovery.main()
            current = budget.snapshot()
            self.assertEqual(current['events'], original['events'])
            self.assertEqual(current['spent_cny'], original['spent_cny'])
            audit = current['recoveries'][-1]
            self.assertEqual(json.loads(Path(audit['backup']).read_text()), original)
            self.assertEqual(audit['unknown_reservation_retained'], .128472)


if __name__ == '__main__':
    unittest.main()

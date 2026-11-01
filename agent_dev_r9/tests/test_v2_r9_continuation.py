"""Continue two missing conditions without retrying a failed or completed condition."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import resume_r9_diagnostics as resume
from stbench.campaign import configuration
from stbench.evaluation import atomic_json


class DiagnosticContinuation(unittest.TestCase):
    def inputs(self):
        plan=dict(incremental_cap_cny=10,total_authorized_cny=75,baseline_spent_cny=34.011998,cumulative_ceiling_cny=44.011998)
        event=dict(request_id='disconnect',status='reserved',phase='final',reserved_cny=.125273,created_at=1000.,
            phase_ceiling_cny=44.011998,request=dict(model='MiniMax-M2.7',protocol='chat',timeout_seconds=420,max_output_tokens=16384))
        state=dict(version=3,limit_cny=75,spent_cny=34.887482,halted='Unconfirmed upstream result; reservation retained',
            halt_details=dict(category='upstream_unconfirmed',model='MiniMax-M2.7',protocol='chat',event_index=1),
            events=[dict(request_id='older',status='reserved',reserved_cny=.659229),event])
        record=dict(pid='self-hard-07',model='MiniMax-M2.7',provider='openai-compat',experiment_kind='live',
            max_iters=1,stop_reason='provider_error',error=resume.ERROR,started_at=999.,finished_at=1097.4,
            attempts=[dict(provider_error=resume.ERROR,code='',actual_model='',prompt_tokens=0,completion_tokens=0,cost_cny=0.)])
        checkpoint=dict(action='user_continue_remaining_diagnostic_jobs',ledger_state_sha256=resume.state_hash(state),
            event_count=2,spent_cny=state['spent_cny'],request_id='disconnect')
        return plan,state,record,checkpoint

    def test_reviewed_disconnect_is_identified_with_original_ceiling(self):
        plan,state,record,checkpoint=self.inputs()
        resume.validate_disconnect(state,record,plan,checkpoint)
        self.assertEqual(resume.scoped_budget(configuration('config.r9_diagnostic.json'),plan).ceiling(),44.011998)

    def test_a_different_or_newer_failure_cannot_use_the_old_checkpoint(self):
        plan,state,record,checkpoint=self.inputs()
        for change in [dict(spent_cny=35.),dict(halted='Paused by user'),dict(events=state['events']+[state['events'][-1]])]:
            with self.subTest(change=change),self.assertRaises(RuntimeError):
                resume.validate_disconnect(state|change,record,plan,checkpoint)

    def test_known_receipts_wrong_faults_and_recovered_requests_are_rejected(self):
        plan,state,record,checkpoint=self.inputs()
        for change in ('receipt','timeout','recovered','settled'):
            s=copy.deepcopy(state);r=copy.deepcopy(record)
            if change=='receipt':r['attempts'][0]['actual_model']='MiniMax-M2.7'
            if change=='timeout':r['error']='Upstream wall deadline exceeded; no automatic retry'
            if change=='recovered':s['recoveries']=[dict(request_id='disconnect')]
            if change=='settled':s['events'][-1]['status']='settled'
            cp=checkpoint|dict(ledger_state_sha256=resume.state_hash(s))
            with self.subTest(change=change),self.assertRaises(RuntimeError):resume.validate_disconnect(s,r,plan,cp)

    def test_all_existing_conditions_including_the_failed_one_are_skipped(self):
        jobs=[dict(pid='p',framework=fw,variant=variant) for fw in ('custom','codex') for variant in ('baseline','concise')]
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for job in jobs[:2]:
                atomic_json(root/'jobs'/(job['framework']+'_'+job['variant'])/'p.json',dict(attempts=[dict(provider_error=resume.ERROR)]))
            self.assertEqual(resume.remaining_jobs(root,dict(jobs=jobs)),jobs[2:])

    def test_an_existing_empty_record_is_not_silently_reissued(self):
        job=dict(pid='p',framework='custom',variant='baseline')
        for kind in ('empty','request_trace'):
            with self.subTest(kind=kind),tempfile.TemporaryDirectory() as directory:
                root=Path(directory);folder=root/'jobs/custom_baseline';folder.mkdir(parents=True)
                if kind=='empty':atomic_json(folder/'p.json',dict(attempts=[]))
                else:(folder/'p.request.txt').write_text('already issued',encoding='utf-8')
                with self.assertRaises(RuntimeError):resume.remaining_jobs(root,dict(jobs=[job]))

    def test_release_keeps_every_event_amount_and_backup_and_is_one_time(self):
        plan,state,record,checkpoint=self.inputs()
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);ledger=root/'evidence/dmxapi_budget_75.json'
            cfg=configuration('config.r9_diagnostic.json');cfg.update(platform_root=directory,budget_ledger_path=str(ledger),campaign_root=directory)
            atomic_json(ledger,state);raw=ledger.read_bytes();history=root/'history';history.mkdir()
            with patch.object(resume,'registered_process_alive',return_value=False):
                receipt=resume.release_disconnect(cfg,plan,checkpoint,record,history,dict(resume_id='one'))
                after=json.loads(ledger.read_bytes())
                self.assertEqual(after['events'],state['events']);self.assertEqual(after['spent_cny'],state['spent_cny'])
                self.assertEqual((history/'ledger_before_resume.json').read_bytes(),raw)
                self.assertEqual(receipt['current_unknown_retained'],.125273)
                self.assertEqual(receipt['cumulative_ceiling_cny'],44.011998)
                with self.assertRaises(RuntimeError):resume.release_disconnect(cfg,plan,checkpoint,record,history,dict(resume_id='two'))

    def test_live_process_blocks_release_without_changing_the_ledger(self):
        plan,state,record,checkpoint=self.inputs()
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);ledger=root/'evidence/dmxapi_budget_75.json'
            cfg=configuration('config.r9_diagnostic.json');cfg.update(platform_root=directory,budget_ledger_path=str(ledger),campaign_root=directory)
            atomic_json(ledger,state);raw=ledger.read_bytes()
            with patch.object(resume,'registered_process_alive',return_value=True),self.assertRaises(RuntimeError):
                resume.release_disconnect(cfg,plan,checkpoint,record,root,dict(resume_id='duplicate'))
            self.assertEqual(ledger.read_bytes(),raw)


if __name__=='__main__':unittest.main()

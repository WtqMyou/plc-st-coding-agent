"""The readiness study must fit the inherited cap and count actual judge work."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import r9_four_group_readiness as study
from stbench.campaign import configuration,digest
from stbench.evaluation import atomic_json
from stbench.transport import MeteredProvider


class Stage3Readiness(unittest.TestCase):
    def setup_inputs(self,directory):
        cfg=configuration(str(study.CONFIG));cfg['platform_root']=directory
        cfg['budget_ledger_path']=str(Path(directory)/'evidence/dmxapi_budget_75.json')
        cfg['campaign_root']=str(Path(directory)/'run')
        state=dict(version=3,limit_cny=75,spent_cny=36.373218,halted='',events=[dict(status='reserved',reserved_cny=.78450215)])
        atomic_json(Path(cfg['budget_ledger_path']),state)
        origin=json.loads((ROOT/'ORIGIN_R8.json').read_text(encoding='utf-8'))
        proof=dict(passed=True,source_sha256=digest(),deadline_checks={k:True for k in ('cli_tree_deadline',
            'upstream_failure_aborts_cli','single_upstream_request','full_request_window','request_window_keeps_best','genuine_timeout_keeps_halt')})
        return cfg,state,origin,proof

    def test_two_models_two_frameworks_share_limits_and_all_repairs_fit(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state,origin,proof=self.setup_inputs(directory);plan=study.build_plan(cfg,state,origin,proof)
            self.assertEqual(len(plan['jobs']),8);self.assertEqual(plan['maximum_requests'],16)
            self.assertLess(plan['worst_reservation_cny'],7.5)
            self.assertEqual(plan['cumulative_ceiling_cny'],43.873218)
            self.assertEqual(study.study_budget(cfg,plan).ceiling(),43.873218)
            self.assertEqual({(j['framework'],j['model_id']) for j in plan['jobs']},
                {(fw,mid) for fw in ('custom','codex') for mid in ('deepseek-v4pro','minimax-m27')})
            self.assertTrue(all(j['task_seconds']==1200 and not j['verification_after_tests'] for j in plan['jobs']))

    def test_nested_model_check_execution_is_counted_with_missing_jobs_in_denominator(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state,origin,proof=self.setup_inputs(directory);plan=study.build_plan(cfg,state,origin,proof)
            root=Path(cfg['campaign_root']);atomic_json(root/'ledger_before_study.json',state)
            job=plan['jobs'][0]
            atomic_json(root/'jobs'/job['condition']/(job['pid']+'.json'),dict(attempts=[
                dict(idx=0,code='code',judge=dict(model_check=dict(executed=True)),tests_passed=1)],
                solved=False,first_try=False,best_attempt=0))
            summary=study.collect(cfg,plan)
            self.assertEqual(summary['recorded'],1);self.assertEqual(summary['planned'],8)
            self.assertEqual(sum(r['mc_executed'] for r in summary['rows']),1)
            self.assertTrue(all(r['n']==2 and r['tests_total']==37 for r in summary['rows']))
            self.assertTrue(summary['all_original_events_preserved'])

    def test_responses_capture_preserves_text_without_copying_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state,origin,proof=self.setup_inputs(directory);plan=study.build_plan(cfg,state,origin,proof)
            budget=study.study_budget(cfg,plan);job=plan['jobs'][0]
            provider=MeteredProvider(cfg['models'][0],budget,protocol='responses',max_tokens=16384,timeout=420,offline=True)
            folder=Path(directory)/'traces'
            study.guarded_capture(provider,budget,plan,job,{job['job_id']:1.},folder)
            provider.before_send([dict(role='user',content='task')])
            provider.response_observer(dict(model='deepseek-v4-pro-0813',status='completed',usage={},output=[
                dict(type='message',content=[dict(type='output_text',text='FUNCTION_BLOCK FB END_FUNCTION_BLOCK')])]),'responses')
            data=json.loads((folder/(job['pid']+'.response_01.json')).read_text(encoding='utf-8'))
            self.assertIn('FUNCTION_BLOCK',data['message']['content']);self.assertEqual(data['protocol'],'responses')


if __name__=='__main__':unittest.main()

"""Unsent budget stops differ from charged incomplete generations and pilot readiness."""
import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock
from unittest.mock import patch
from types import SimpleNamespace
import sys
from stbench.billing import CampaignBudget,PHASES
from stbench.campaign import configuration,group_order,pilot_ready
from stbench.harness.engine import Solver,solve_problem,summarize
from stbench.providers.base import ProviderError
from stbench.schema import Problem
from stbench.transport import MeteredProvider
from stbench.codex_baseline import CodexProvider
from stbench import campaign
from stbench.transport import RequestDeadline


def problem():
    return Problem.from_dict(dict(pid='accounting',source='selfmade',title='test',difficulty='easy',requirements='true',
        variables=[dict(name='out',data_type='BOOL',direction='output')],
        test_cases=[dict(tc_id='case',inputs={},expected={'out':True})]))


class CampaignAccounting(unittest.TestCase):
    def provider(self,budget,sender):
        p=MeteredProvider(dict(model='test-model',base_url='https://example.invalid/v1',api_key_env='UNUSED',
            input_cny_per_million=1,output_cny_per_million=2),budget,offline=True,sender=sender,max_tokens=16)
        p.name='openai-compat'  # exercise live accounting with a strictly local fake sender
        return p

    def test_unsent_budget_stop_is_not_an_attempt_and_keeps_the_full_denominator(self):
        with tempfile.TemporaryDirectory() as d:
            b=CampaignBudget(Path(d)/'budget.json','preflight');b.reserve(5)
            sender=Mock(side_effect=AssertionError('An exhausted budget must never send'))
            record=solve_problem(problem(),Solver(self.provider(b,sender),model_check=False,max_iters=1))
            self.assertEqual(record.stop_reason,'budget_exhausted');self.assertEqual(record.attempts,[])
            self.assertEqual(summarize([record])['tests_total'],1)
            self.assertEqual(summarize([record])['budget_stopped_tasks'],1)
            self.assertEqual(len(b.snapshot()['events']),1);sender.assert_not_called()

    def test_charged_truncation_has_known_cost_but_is_still_a_failed_candidate(self):
        with tempfile.TemporaryDirectory() as d:
            b=CampaignBudget(Path(d)/'budget.json','preflight')
            sender=lambda *args:dict(model='test-model',usage=dict(prompt_tokens=2,completion_tokens=16),
                choices=[dict(finish_reason='length',message=dict(content='partial'))])
            record=solve_problem(problem(),Solver(self.provider(b,sender),model_check=False,max_iters=1))
            row=summarize([record]);self.assertFalse(record.solved)
            self.assertEqual(len(record.attempts),1);self.assertGreater(row['total_cost_cny'],0)
            self.assertEqual(row['cost_unknown_attempts'],0);self.assertEqual(row['known_incomplete_attempts'],1)

    def test_phase_reallocation_is_explicit_preserves_prior_reservations_and_total_limit(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'budget.json';old=CampaignBudget(path,'preflight');old.reserve(4.75)
            before=old.snapshot();caps=dict(PHASES,preflight=8)
            proposed=CampaignBudget(path,'preflight',phase_caps=caps)
            self.assertEqual(proposed.snapshot(),before);self.assertEqual(proposed.remaining(),3.25)
            self.assertEqual(old.remaining(),.25)
            proposed.reserve(.5);self.assertEqual(proposed.snapshot()['events'][-1]['phase_ceiling_cny'],8)
            for invalid in [dict(caps,retest=76),dict(caps,final=70),dict(caps,preflight=21),dict(caps,preflight=True)]:
                with self.assertRaises(ProviderError):CampaignBudget(path,'preflight',phase_caps=invalid)

    def test_pilot_accepts_recorded_failures_but_not_unsent_jobs_or_missing_conditions(self):
        cfg=configuration('')
        rows=[dict(framework=fw,model_id=mid,n=6,attempted=6,generated=1) for fw,mid in group_order(cfg)]
        self.assertTrue(pilot_ready(cfg,rows))
        for key,value in [('attempted',5),('generated',0)]:
            changed=copy.deepcopy(rows);changed[0][key]=value;self.assertFalse(pilot_ready(cfg,changed))
        self.assertFalse(pilot_ready(cfg,rows[:-1]));self.assertFalse(pilot_ready(cfg,[rows[0]]*4))

    def test_known_truncation_can_use_a_bounded_feedback_repair_without_an_empty_assistant_message(self):
        with tempfile.TemporaryDirectory() as d:
            b=CampaignBudget(Path(d)/'budget.json','preflight');sent=[]
            code='FUNCTION_BLOCK FB VAR_OUTPUT out:BOOL; END_VAR out:=TRUE; END_FUNCTION_BLOCK'
            def sender(url,payload,*args):
                sent.append(payload['messages'])
                return dict(model='test-model',usage=dict(prompt_tokens=2,completion_tokens=16 if len(sent)==1 else 8),
                    choices=[dict(finish_reason='length' if len(sent)==1 else 'stop',
                                  message=dict(content='partial' if len(sent)==1 else code))])
            record=solve_problem(problem(),Solver(self.provider(b,sender),model_check=False,max_iters=3))
            self.assertTrue(record.solved);self.assertEqual(len(sent),2);self.assertEqual(record.error,'')
            self.assertEqual(len(record.attempts),2);self.assertGreater(record.attempts[0].cost_cny,0)
            self.assertIn('截断',sent[1][-1]['content'])
            self.assertFalse(any(m['role']=='assistant' and not m['content'] for m in sent[1]))
            self.assertEqual(summarize([record])['known_incomplete_attempts'],1)

    def test_unknown_usage_still_stops_after_one_request_without_feedback_retry(self):
        with tempfile.TemporaryDirectory() as d:
            b=CampaignBudget(Path(d)/'budget.json','preflight');sender=Mock(return_value={'model':'test-model'})
            record=solve_problem(problem(),Solver(self.provider(b,sender),model_check=False,max_iters=5))
            self.assertEqual(sender.call_count,1);self.assertEqual(record.stop_reason,'provider_error')
            self.assertTrue(b.read(allow_halted=True)['halted']);self.assertEqual(summarize([record])['cost_unknown_attempts'],1)

    def test_cli_failure_before_contact_does_not_reuse_a_previous_candidates_charge(self):
        with tempfile.TemporaryDirectory() as d:
            transport=SimpleNamespace(timeout=420,last_charge=.4,last_receipt={'model':'old'})
            gateway=SimpleNamespace(provider=transport,url='http://127.0.0.1:1',token='local-only')
            cli=CodexProvider(gateway,model='test-model',work_root=Path(d),executable=sys.executable,timeout=450)
            with patch('stbench.codex_baseline.run_logged',return_value=(1,False,None)) as run:
                # The fake process must still supply the diagnostic file expected by the adapter.
                def failed(*args,**kw):
                    (kw['work']/'events.jsonl').write_text('');return (1,False,None)
                run.side_effect=failed
                with self.assertRaises(ProviderError):cli.generate([{'role':'user','content':'test'}])
            self.assertEqual(cli.last_charge,0);self.assertEqual(cli.last_receipt,{})

    def run_fake_pilot(self,d,sender):
        cfg=configuration('');cfg['platform_root']=d
        cfg['budget_ledger_path']=str(Path(d)/'evidence/dmxapi_budget_75.json')
        for spec in cfg['models']:spec['generation_protocol']='chat'
        class Backend:
            timeout=120
            def identity(self):return {'platform':'test-only'}
        def factory(spec,budget,**kw):
            p=MeteredProvider(spec,budget,offline=True,sender=sender,**kw);p.name='openai-compat';return p
        with patch.object(campaign,'MeteredProvider',side_effect=factory), \
             patch.object(campaign,'CodesysBackend',return_value=Backend()), \
             patch.object(campaign,'OpenPLCBackend',return_value=Backend()):
            return campaign.run_stage(cfg,Path(d),'pilot',{s['id']:'chat' for s in cfg['models']},
                only_job=('custom',cfg['models'][0]['id'],'self-easy-02'))

    def test_unknown_failure_records_wall_time_before_writing_the_partial_report(self):
        with tempfile.TemporaryDirectory() as d:
            def sender(*args):raise RequestDeadline('Upstream wall deadline exceeded; no automatic retry')
            with self.assertRaises(ProviderError):self.run_fake_pilot(d,sender)
            import json
            folder=Path(d)/'pilot';timing=json.loads((folder/'custom_deepseek-v4pro/self-easy-02.timing.json').read_text())
            rows=json.loads((folder/'summary.json').read_text())
            self.assertGreater(timing['active_wall_seconds'],0)
            self.assertEqual(rows[0]['group_active_wall_seconds'],timing['active_wall_seconds'])

    def test_resuming_an_exhausted_pilot_preserves_its_original_time_and_charge(self):
        with tempfile.TemporaryDirectory() as d:
            sender=Mock(return_value=dict(model='deepseek-v4-pro-0813',usage=dict(prompt_tokens=2,completion_tokens=16384),
                choices=[dict(finish_reason='length',message=dict(content='partial'))]))
            self.run_fake_pilot(d,sender)
            folder=Path(d)/'pilot/custom_deepseek-v4pro'
            paths=[folder/'self-easy-02.json',folder/'self-easy-02.timing.json',Path(d)/'evidence/dmxapi_budget_75.json']
            before=[p.read_bytes() for p in paths]
            self.run_fake_pilot(d,sender)
            self.assertEqual(sender.call_count,1);self.assertEqual([p.read_bytes() for p in paths],before)


if __name__=='__main__':unittest.main()

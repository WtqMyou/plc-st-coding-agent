"""Coverage, privacy and single-request billing controls without external calls."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO/'progress/tools'))
import review_r8_first_candidate as study
from stbench.transport import MeteredProvider as ActualTransport
from stbench.providers.base import ProviderError
from stbench.schema import Problem


class FirstCandidateStudy(unittest.TestCase):
    def inputs(self,directory):
        cfg=study.configuration(str(study.CONFIG));cfg=copy.deepcopy(cfg)
        cfg['platform_root']=directory;cfg['budget_ledger_path']=str(Path(directory)/'evidence/dmxapi_budget_75.json')
        cfg['campaign_root']=str(Path(directory)/'study')
        state=dict(version=3,limit_cny=75,spent_cny=study.BASELINE,halted='',events=[],recoveries=[])
        study.atomic_json(Path(cfg['budget_ledger_path']),state)
        plan=study.plan_for(cfg,state);Path(cfg['campaign_root']).mkdir()
        study.atomic_json(Path(cfg['campaign_root'])/'study_plan.json',plan)
        return cfg,state,plan

    def test_twelve_jobs_three_per_group(self):
        jobs=study.jobs();self.assertEqual(len(jobs),12);self.assertEqual(len({j['job_id'] for j in jobs}),12)
        for condition in {j['condition'] for j in jobs}:
            self.assertEqual({j['pid'] for j in jobs if j['condition']==condition},set(study.PIDS))

    def test_order_rotates_without_changing_models(self):
        jobs=study.jobs()
        self.assertEqual([j['condition'] for j in jobs[:4]],[j['condition'] for j in jobs[4:8]][::-1])
        self.assertNotEqual(jobs[0]['condition'],jobs[8]['condition'])

    def test_current_contract_cases_and_interfaces(self):
        data=study.selected();self.assertEqual([len(data[p].test_cases) for p in study.PIDS],[25,40,36])
        self.assertIn('CycleMs',{x.name for x in data['public-easy-04'].variables})
        study.verify_data()

    def test_formal_budget_is_thirty_seconds_without_mutating_data(self):
        self.assertEqual({p.mc_max_seconds for p in study.selected().values()},{30.})
        stored={p.pid:p for p in study.v.problems()}
        self.assertEqual({stored[pid].mc_max_seconds for pid in study.PIDS},{60.})

    def test_messages_do_not_include_reference_or_test_payload(self):
        cfg=study.configuration(str(study.CONFIG));data=study.selected()
        for job in study.jobs():
            p=data[job['pid']];messages=study.messages_for(cfg,job,p);text=json.dumps(messages,ensure_ascii=False)
            self.assertNotIn(study.v.reference(p),text)
            self.assertNotIn('"test_cases"',text);self.assertNotIn('"expect_full"',text)

    def test_all_twelve_reservations_fit_five_yuan(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state,plan=self.inputs(directory)
            self.assertEqual(plan['maximum_new_requests'],12)
            self.assertLess(plan['worst_reservation_cny'],5)
            self.assertEqual(study.budget_for(cfg,plan).ceiling(),43.409603)

    def test_large_measured_envelopes_fail_before_live(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state,plan=self.inputs(directory)
            with self.assertRaises(RuntimeError):study.plan_for(cfg,state,[dict(job_id=j['job_id'],upstream_message_bytes=10000000) for j in study.jobs()])

    def test_changed_model_parameters_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state,plan=self.inputs(directory);cfg['models'][0]['parameters']={}
            with self.assertRaises(RuntimeError):study.plan_for(cfg,state)

    def test_changed_candidate_policy_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state,plan=self.inputs(directory);cfg['limits']['max_candidates']=2
            with self.assertRaises(RuntimeError):study.plan_for(cfg,state)

    def test_budget_cap_cannot_be_forged(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state,plan=self.inputs(directory)
            with self.assertRaises(RuntimeError):study.budget_for(cfg,plan|dict(cumulative_ceiling_cny=75))

    def test_halted_or_drifted_ledger_is_not_reset(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state,plan=self.inputs(directory)
            with self.assertRaises(RuntimeError):study.plan_for(cfg,state|dict(halted='unknown usage'))
            with self.assertRaises(RuntimeError):study.plan_for(cfg,state|dict(spent_cny=39))

    def setup_transport(self,directory,*,finish='stop',content='FUNCTION_BLOCK FB END_FUNCTION_BLOCK',model_identity=None):
        cfg,state,plan=self.inputs(directory);budget=study.budget_for(cfg,plan)
        spec=next(m for m in cfg['models'] if m['id']=='minimax-m27')
        job=next(j for j in plan['jobs'] if j['framework']=='custom' and j['model_id']==spec['id'])
        calls=[]
        def sender(url,payload,key,timeout):
            calls.append(payload)
            return dict(model=model_identity or spec['model'],usage=dict(prompt_tokens=1,completion_tokens=2),
                choices=[dict(finish_reason=finish,message=dict(content=content,reasoning_content='fixture reasoning'))])
        transport=ActualTransport(spec,budget,max_tokens=16384,protocol='chat',sender=sender,offline=True)
        folder=Path(directory)/'traces';folder.mkdir()
        pending={j['job_id']:j['first_upper_cny'] for j in plan['jobs']}
        count=study.capture(transport,budget,job,pending,folder)
        return cfg,plan,budget,transport,job,pending,count,calls,folder

    def test_second_request_is_blocked_before_sender(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,plan,budget,transport,job,pending,count,calls,folder=self.setup_transport(directory)
            transport.generate([dict(role='user',content='fixture')])
            with self.assertRaises(ProviderError):transport.generate([dict(role='user',content='fixture')])
            self.assertEqual(len(calls),1);self.assertEqual(len(budget.read()['events']),1)

    def test_pending_jobs_are_protected(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,plan,budget,transport,job,pending,count,calls,folder=self.setup_transport(directory)
            transport.generate([dict(role='user',content='fixture')])
            expected=sum(study.money(x) for key,x in pending.items() if key!=job['job_id'])
            self.assertEqual(study.money(budget.protected_cny),expected)

    def test_empty_length_response_is_recorded_once_and_settled(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,plan,budget,transport,job,pending,count,calls,folder=self.setup_transport(directory,finish='length',content='')
            with self.assertRaises(ProviderError):transport.generate([dict(role='user',content='fixture')])
            self.assertEqual(len(calls),1);self.assertEqual(budget.read()['events'][0]['status'],'settled')
            self.assertEqual(study.load(folder/(job['pid']+'.response_01.json'))['message']['content'],'')

    def test_model_identity_failure_keeps_unknown_reserve(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,plan,budget,transport,job,pending,count,calls,folder=self.setup_transport(directory,model_identity='wrong-model')
            with self.assertRaises(ProviderError):transport.generate([dict(role='user',content='fixture')])
            ledger=study.load(cfg['budget_ledger_path'])
            self.assertTrue(ledger['halted']);self.assertEqual(ledger['events'][0]['status'],'reserved')
            self.assertEqual(len(calls),1)

    def test_request_bound_violation_never_contacts_sender(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,plan,budget,transport,job,pending,count,calls,folder=self.setup_transport(directory)
            with self.assertRaises(ProviderError):transport.generate([dict(role='user',content='X'*1000000)])
            self.assertEqual(len(calls),0);self.assertEqual(len(budget.read()['events']),0)

    def test_existing_request_file_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,plan,budget,transport,job,pending,count,calls,folder=self.setup_transport(directory)
            path=folder/(job['pid']+'.request_01.json');path.write_text('old',encoding='utf8')
            with self.assertRaises(ProviderError):transport.generate([dict(role='user',content='fixture')])
            self.assertEqual(path.read_text('utf8'),'old');self.assertFalse(calls)

    def test_invalid_code_still_produces_only_one_candidate(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state,plan=self.inputs(directory);job=next(j for j in plan['jobs'] if j['framework']=='custom' and j['model_id']=='minimax-m27')
            budget=study.budget_for(cfg,plan);calls=[]
            def sender(*args):
                calls.append(1)
                return dict(model='MiniMax-M2.7',usage=dict(prompt_tokens=1,completion_tokens=2),choices=[dict(finish_reason='stop',message=dict(content='not ST'))])
            def factory(spec,budget,**kwargs):return ActualTransport(spec,budget,**kwargs,sender=sender,offline=True)
            with patch.object(study,'MeteredProvider',factory):
                out=study.generate_job(cfg,plan,job,budget,{j['job_id']:j['first_upper_cny'] for j in plan['jobs']},study.selected())
            self.assertEqual(len(calls),1);self.assertEqual(len(out['attempts']),1)
            self.assertFalse(out['solved']);self.assertFalse(out['complete_code'])

    def test_responses_payload_keeps_model_parameters_and_output_cap(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg,state,plan=self.inputs(directory);budget=study.budget_for(cfg,plan)
            spec=next(m for m in cfg['models'] if m['id']=='deepseek-v4pro');calls=[]
            def sender(url,payload,key,timeout):
                calls.append(payload)
                return dict(model=spec['model'],status='completed',usage=dict(input_tokens=1,output_tokens=1),
                    output=[dict(type='message',content=[dict(type='output_text',text='FUNCTION_BLOCK FB END_FUNCTION_BLOCK')])])
            transport=ActualTransport(spec,budget,max_tokens=16384,protocol='responses',sender=sender,offline=True)
            transport.generate([dict(role='user',content='fixture')])
            self.assertEqual(len(calls),1);self.assertEqual(calls[0]['max_output_tokens'],16384)
            self.assertEqual(calls[0]['reasoning'],spec['parameters']['reasoning'])
            self.assertFalse(calls[0]['store'])


if __name__=='__main__':unittest.main()

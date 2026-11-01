"""Money, bridge and validation invariants before any real model calls."""
import json
from contextlib import nullcontext
from types import SimpleNamespace
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from stbench.billing import CampaignBudget,canonical_ledger
from stbench.transport import MeteredProvider,validate_response,responses_messages,HTTPFailure
from stbench.providers.base import ProviderError
from stbench.campaign import configuration,group_order,require_freeze
from stbench import campaign
from stbench.evaluation import StageResult

def response(text='code',finish='stop',model='model'):
    return dict(model=model,choices=[dict(finish_reason=finish,message=dict(content=text))],
                usage=dict(prompt_tokens=10,completion_tokens=20))

class Campaign(unittest.TestCase):
    def spec(self):return dict(model='model',base_url='https://example.invalid/v1',api_key_env='UNUSED',
                               input_cny_per_million=1,output_cny_per_million=2)
    def test_native_import_does_not_swallow_inline_declarations(self):
        from stbench.platforms import split_st
        r=split_st('FUNCTION_BLOCK FB VAR_INPUT a:BOOL; END_VAR VAR_OUTPUT b:BOOL; END_VAR b:=a; END_FUNCTION_BLOCK')
        self.assertEqual(r['implementation'],'b:=a;')
        self.assertNotIn('b:=a',r['declaration'])
    def test_phase_carry_and_formal_protection(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'ledger.json';b=CampaignBudget(p,'preflight')
            i=b.reserve(4);b.settle(i,2)
            dev=CampaignBudget(p,'development');self.assertEqual(dev.remaining(),18)
            with self.assertRaises(ProviderError):dev.reserve(19)
            self.assertEqual(CampaignBudget(p,'final').remaining(),63)
    def test_repair_cannot_spend_unvisited_first_candidates(self):
        with tempfile.TemporaryDirectory() as d:
            b=CampaignBudget(Path(d)/'ledger.json','preflight');b.protected_cny=4.5
            with self.assertRaises(ProviderError):b.reserve(.6)
            b.reserve(.5)
    def test_restart_retains_unknown_reservation(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'ledger.json';CampaignBudget(p,'preflight').reserve(.75)
            self.assertEqual(CampaignBudget(p,'preflight').remaining(),4.25)
    def test_settlement_once_and_nonfinite_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            b=CampaignBudget(Path(d)/'ledger.json','preflight');i=b.reserve(1);b.settle(i,.2)
            for value in (float('nan'),-1,True):
                with self.assertRaises(ProviderError):b.reserve(value)
            with self.assertRaises(ProviderError):b.settle(i,.1)
    def test_unknown_usage_halts_whole_campaign(self):
        with tempfile.TemporaryDirectory() as d:
            b=CampaignBudget(Path(d)/'ledger.json','preflight')
            data=response();data.pop('usage')
            p=MeteredProvider(self.spec(),b,offline=True,sender=lambda *args:data)
            with self.assertRaises(ProviderError):p.generate([])
            with self.assertRaises(ProviderError):CampaignBudget(b.path,'final').reserve(.01)
    def test_truncated_is_charged_but_never_a_valid_candidate(self):
        with tempfile.TemporaryDirectory() as d:
            b=CampaignBudget(Path(d)/'ledger.json','preflight')
            p=MeteredProvider(self.spec(),b,offline=True,sender=lambda *args:response(finish='length'))
            with self.assertRaises(ProviderError):p.generate([])
            self.assertGreater(p.last_charge,0)
            self.assertEqual(b.snapshot()['events'][0]['status'],'settled')
    def test_identity_empty_or_missing_usage_cannot_pass(self):
        for data in [response(model='alias'),response(text=''),response(finish='length')]:
            if data['model']=='alias':
                with self.assertRaises(ProviderError):validate_response(data,'chat',['model'])
            else:self.assertFalse(validate_response(data,'chat',['model'])['complete'])
    def test_responses_roles_and_text_preserved(self):
        m=responses_messages(dict(instructions='system',input=[dict(role='developer',content='rules'),
            dict(role='user',content=[dict(type='input_text',text='task')]),dict(role='assistant',content='best')]))
        self.assertEqual([x['role'] for x in m],['system','system','user','assistant'])
        self.assertEqual([x['content'] for x in m],['system','rules','task','best'])
        for job in [dict(previous_response_id='old'),dict(input=[dict(type='function_call_output')]),
                    dict(input=[dict(role='user',content=[dict(type='input_image')])])]:
            with self.assertRaises(ProviderError):responses_messages(job)
    def test_canonical_ledger_independent_of_run_folder(self):
        cfg=configuration('');p=canonical_ledger(cfg)
        cfg['campaign_root']='another-output';self.assertEqual(canonical_ledger(cfg),p)
        cfg['budget_ledger_path']='another-ledger'
        with self.assertRaises(ProviderError):canonical_ledger(cfg)
    def test_order_is_interleaved_and_freeze_rejects_change(self):
        cfg=configuration('');self.assertEqual([x[0] for x in group_order(cfg)],['custom','codex','custom','codex'])
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'freeze.json';require_freeze(p,{'version':1});require_freeze(p,{'version':1})
            with self.assertRaises(ProviderError):require_freeze(p,{'version':2})
    def test_identity_case_only_is_allowed_but_other_alias_is_rejected(self):
        valid=validate_response(response(model='minimax-m2.7'),'chat',['MiniMax-M2.7'])
        self.assertTrue(valid['complete'])
        with self.assertRaises(ProviderError):
            validate_response(response(model='minimax-m2.7-other'),'chat',['MiniMax-M2.7'])
    def test_audited_recovery_preserves_unknown_charges_and_original_events(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'ledger.json';b=CampaignBudget(p,'preflight')
            b.reserve(.5);b.halt('Unconfirmed upstream result; reservation retained')
            evidence=dict(requested_model='MiniMax-M2.7',observed_model='minimax-m2.7',
                finish_reason='stop',usage=dict(prompt_tokens=5,completion_tokens=10))
            state=json.loads(p.read_text());state['events'].append(dict(status='settled',
                model='MiniMax-M2.7',purpose='one bounded identity diagnosis',metadata=evidence))
            p.write_text(json.dumps(state));audit=Path(d)/'audit.json';audit.write_text(json.dumps(evidence))
            recovery=b.recover_identity(audit,'MiniMax-M2.7');current=b.snapshot()
            self.assertEqual(current['spent_cny'],state['spent_cny'])
            self.assertEqual(current['events'],state['events'])
            self.assertEqual(json.loads(Path(recovery['backup']).read_text()),state)
            self.assertEqual(recovery['retained_reservations'],.5)
            with self.assertRaises(ProviderError):b.recover_identity(audit,'MiniMax-M2.7')
    def test_recovery_cannot_clear_other_halts_or_unlinked_evidence(self):
        with tempfile.TemporaryDirectory() as d:
            b=CampaignBudget(Path(d)/'ledger.json','preflight')
            evidence=dict(requested_model='model',observed_model='MODEL',finish_reason='stop',
                usage=dict(prompt_tokens=1,completion_tokens=1))
            p=Path(d)/'audit.json';p.write_text(json.dumps(evidence))
            b.halt('Charge exceeded reservation')
            with self.assertRaises(ProviderError):b.recover_identity(p,'model')
            s=json.loads(b.path.read_text());s['halted']='Unconfirmed upstream result; reservation retained'
            b.path.write_text(json.dumps(s))
            with self.assertRaises(ProviderError):b.recover_identity(p,'model')
    def test_old_identity_audit_cannot_clear_a_later_transport_failure(self):
        with tempfile.TemporaryDirectory() as d:
            b=CampaignBudget(Path(d)/'ledger.json','preflight')
            evidence=dict(requested_model='model',observed_model='MODEL',finish_reason='stop',
                usage=dict(prompt_tokens=1,completion_tokens=1))
            p=Path(d)/'audit.json';p.write_text(json.dumps(evidence))
            b.reserve(.01)
            state=b.snapshot();state['events'][0].update(status='settled',model='model',
                purpose='one bounded identity diagnosis',metadata=evidence)
            b.path.write_text(json.dumps(state))
            b.reserve(.5);b.halt('Unconfirmed upstream result; reservation retained')
            with self.assertRaisesRegex(ProviderError,'predates'):
                b.recover_identity(p,'model')
            state=json.loads(b.path.read_text());state['halt_details']=dict(category='upstream_unconfirmed',model='model')
            b.path.write_text(json.dumps(state))
            with self.assertRaisesRegex(ProviderError,'non-identity'):
                b.recover_identity(p,'model')
    def test_protocol_probe_resumes_without_rebilling_completed_model(self):
        with tempfile.TemporaryDirectory() as d:
            out=Path(d);cfg=configuration('');cfg['platform_root']=d
            cfg['budget_ledger_path']=str(out/'evidence/dmxapi_budget_75.json')
            first,second=cfg['models'];usage=dict(prompt_tokens=1,completion_tokens=1)
            (out/(first['id']+'_protocol.json')).write_text(json.dumps(dict(route='responses',
                chat_model=first['model'],chat_usage=usage,responses_model=first['model'],responses_usage=usage)))
            sent=[]
            def factory(spec,budget,**kw):
                def sender(url,payload,key,timeout):
                    sent.append((spec['id'],url))
                    if url.endswith('/responses'):raise HTTPFailure(404)
                    return response(model=spec['model'].lower())
                return MeteredProvider(spec,budget,offline=True,sender=sender,**kw)
            with patch.object(campaign,'credential_check',return_value={'selected_models':{'a':True,'b':True}}), \
                 patch.object(campaign,'MeteredProvider',side_effect=factory):
                routes=campaign.probe(cfg,out)
                self.assertEqual(routes,{first['id']:'responses',second['id']:'chat'})
                self.assertEqual(len(sent),2)
                campaign.probe(cfg,out)
                self.assertEqual(len(sent),2)
    def test_pilot_settles_sequentially_and_final_still_guards_full_coverage(self):
        with tempfile.TemporaryDirectory() as d:
            cfg=configuration('');cfg['platform_root']=d
            for spec in cfg['models']:spec['generation_protocol']='chat'
            cfg['budget_ledger_path']=str(Path(d)/'evidence/dmxapi_budget_75.json')
            selected=[t for t in campaign.tasks() if t[0].pid in campaign.PILOT]
            total=sum(campaign.first_candidate_bound(s,p,cfg,fw) for _,p,_ in selected
                      for s in cfg['models'] for fw in ('custom','codex'))
            self.assertGreater(total,5)
            sent=[]
            def factory(spec,budget,**kw):
                def sender(*args):
                    sent.append(spec['id']);return response(model=spec['model'])
                return MeteredProvider(spec,budget,offline=True,sender=sender,**kw)
            class Backend:
                timeout=120
                def identity(self):return {'platform':'test'}
                def compile(self,*args):return SimpleNamespace(to_dict=lambda:dict(status='passed',platform_identity=self.identity()))
            def evaluate(code,problem,**kw):
                return StageResult(compiles=True,tests_passed=len(problem.test_cases),tests_total=len(problem.test_cases))
            routes={s['id']:'chat' for s in cfg['models']}
            with patch.object(campaign,'MeteredProvider',side_effect=factory), \
                 patch.object(campaign,'CodesysBackend',return_value=Backend()), \
                 patch.object(campaign,'OpenPLCBackend',return_value=Backend()), \
                 patch.object(campaign,'ResponsesGateway',side_effect=lambda **kw:nullcontext(SimpleNamespace(**kw))), \
                 patch.object(campaign,'CodexProvider',side_effect=lambda gateway,**kw:gateway.provider), \
                 patch('stbench.harness.engine.evaluate',side_effect=evaluate):
                campaign.run_stage(cfg,Path(d),'pilot',routes)
                self.assertEqual(len(sent),24)
                rows=json.loads((Path(d)/'pilot/summary.json').read_text())
                self.assertTrue(all(r['n']==6 and r['generated']==6 for r in rows))
                self.assertLess(CampaignBudget(canonical_ledger(cfg),'preflight').snapshot()['spent_cny'],5)
                ledger=canonical_ledger(cfg);s=json.loads(ledger.read_text());s['spent_cny']=64.99
                ledger.write_text(json.dumps(s))
                with self.assertRaisesRegex(ProviderError,'Remaining first-candidate'):
                    campaign.run_stage(cfg,Path(d),'final',routes)
                self.assertEqual(len(sent),24)

if __name__=='__main__':unittest.main()

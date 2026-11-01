"""Upstream token overrun evidence, settlement failures and shared-protocol cap gates."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from stbench import campaign
from stbench.billing import CampaignBudget
from stbench.providers.base import ProviderError
from stbench.transport import MeteredProvider

def reply(tokens):
    return dict(model='model',choices=[dict(finish_reason='stop',message=dict(content='code'))],
                usage=dict(prompt_tokens=2,completion_tokens=tokens))

class OutputLimits(unittest.TestCase):
    def spec(self,input_rate=1,output_rate=2):
        return dict(model='model',base_url='https://example.invalid/v1',api_key_env='UNUSED',
                    input_cny_per_million=input_rate,output_cny_per_million=output_rate)
    def test_reservation_overrun_preserves_returned_usage_and_known_charge(self):
        with tempfile.TemporaryDirectory() as d:
            b=CampaignBudget(Path(d)/'ledger.json','preflight')
            p=MeteredProvider(self.spec(),b,max_tokens=1,offline=True,sender=lambda *args:reply(5000))
            with self.assertRaises(ProviderError):p.generate([])
            self.assertEqual(p.last_receipt['completion_tokens'],5000)
            self.assertGreater(p.last_charge,0)
            state=b.read(allow_halted=True)
            self.assertEqual(state['halted'],'Charge exceeded reservation')
            self.assertEqual(state['events'][0]['status'],'settled')
            self.assertEqual(state['events'][0]['accounted_cny'],p.last_charge)
    def test_output_overrun_halts_even_when_input_headroom_covers_the_charge(self):
        with tempfile.TemporaryDirectory() as d:
            b=CampaignBudget(Path(d)/'ledger.json','preflight')
            p=MeteredProvider(self.spec(1000,1),b,max_tokens=10,offline=True,sender=lambda *args:reply(100))
            with self.assertRaisesRegex(ProviderError,'output token limit'):p.generate([])
            self.assertEqual(b.read(allow_halted=True)['halted'],'Output token limit exceeded')
            self.assertGreater(p.last_charge,0)
    def test_both_protocols_demonstrate_a_small_cap_and_config_changes_invalidate_it(self):
        with tempfile.TemporaryDirectory() as d:
            cfg=campaign.configuration('');cfg['platform_root']=d
            cfg['budget_ledger_path']=str(Path(d)/'evidence/dmxapi_budget_75.json')
            sent=[]
            def factory(spec,budget,**kw):
                def sender(url,payload,*args):
                    sent.append((spec['model'],url))
                    if url.endswith('/responses'):
                        return dict(model=spec['model'],status='incomplete',output=[],
                                    usage=dict(input_tokens=2,output_tokens=512))
                    return dict(model=spec['model'],choices=[dict(finish_reason='length',message=dict(content='partial'))],
                                usage=dict(prompt_tokens=2,completion_tokens=512))
                return MeteredProvider(spec,budget,offline=True,sender=sender,**kw)
            with patch.object(campaign,'MeteredProvider',side_effect=factory):
                result=campaign.check_output_limits(cfg,Path(d))
            self.assertTrue(result['passed']);self.assertEqual(len(sent),2)
            self.assertTrue(campaign.limits_verified(cfg,Path(d)))
            cfg['models'][0]['generation_protocol']='chat'
            self.assertFalse(campaign.limits_verified(cfg,Path(d)))
    def test_protocol_recovery_preserves_the_overrun_charge_and_is_not_repeatable(self):
        with tempfile.TemporaryDirectory() as d:
            b=CampaignBudget(Path(d)/'ledger.json','preflight')
            p=MeteredProvider(self.spec(),b,max_tokens=1,offline=True,sender=lambda *args:reply(5000))
            with self.assertRaises(ProviderError):p.generate([])
            state=b.read(allow_halted=True)
            path=Path(d)/'validation.json';proof=dict(passed=True,source_sha256='old',generation_protocols={'model':'responses'})
            path.write_text(json.dumps(proof))
            with self.assertRaises(ProviderError):b.recover_output_limit(path,'model')
            proof['source_sha256']=campaign.digest();path.write_text(json.dumps(proof))
            result=b.recover_output_limit(path,'model')
            self.assertEqual(b.snapshot()['events'],state['events']);self.assertEqual(b.snapshot()['spent_cny'],state['spent_cny'])
            self.assertTrue(Path(result['backup']).exists())
            with self.assertRaises(ProviderError):b.recover_output_limit(path,'model')

if __name__=='__main__':unittest.main()

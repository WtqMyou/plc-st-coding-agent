"""Large repairs may use spare budget, while every unvisited first request remains funded."""
from contextlib import nullcontext
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from stbench import campaign
from stbench.billing import CampaignBudget
from stbench.evaluation import StageResult
from stbench.harness.engine import RunRecord
from stbench.providers.base import ProviderResponse
from stbench.harness.engine import Solver,solve_problem
from stbench.schema import Problem
from unittest.mock import Mock


class CoverageScheduling(unittest.TestCase):
    def simulate(self,stage,initial_spend):
        with tempfile.TemporaryDirectory() as d:
            cfg=campaign.configuration('');cfg['platform_root']=d
            cfg['budget_ledger_path']=str(Path(d)/'evidence/dmxapi_budget_75.json')
            budget=CampaignBudget(cfg['budget_ledger_path'],'final')
            if initial_spend:
                i=budget.reserve(initial_spend);budget.settle(i,initial_spend)
            calls=[]
            class Provider:
                name='mock';timeout=420;last_receipt={};last_charge=0
                def __init__(self,spec,budget,**kw):self.model=spec['model'];self.budget=budget;self.before_send=None
                def upper(self,messages):return .2 if any(m['role']=='assistant' for m in messages) else .01
                def generate(self,messages):
                    self.last_charge=0;self.last_receipt={}
                    if self.before_send:self.before_send(messages)
                    i=self.budget.reserve(self.upper(messages));self.budget.settle(i,.001)
                    repair=any(m['role']=='assistant' for m in messages);calls.append(repair)
                    self.last_charge=.001;self.last_receipt={'model':self.model}
                    r=ProviderResponse(text='good' if repair else 'bad',model=self.model,usage={'prompt_tokens':1,'completion_tokens':1})
                    r.cost_cny=.001;return r
            class Backend:
                timeout=120
                def identity(self):return {'platform':'local-simulation-only'}
                def compile(self,*args):return SimpleNamespace(to_dict=lambda:dict(status='passed',platform_identity=self.identity()))
            def evaluate(code,p,**kw):
                return StageResult(compiles=True,tests_passed=len(p.test_cases) if code=='good' else 0,
                    tests_total=len(p.test_cases),platform_results={'codesys':{'status':'passed'}})
            with patch.object(campaign,'MeteredProvider',Provider), \
                 patch.object(campaign,'first_candidate_bound',return_value=.01), \
                 patch.object(campaign,'CodesysBackend',return_value=Backend()), \
                 patch.object(campaign,'OpenPLCBackend',return_value=Backend()), \
                 patch.object(campaign,'ResponsesGateway',side_effect=lambda **kw:nullcontext(SimpleNamespace(**kw))), \
                 patch.object(campaign,'CodexProvider',side_effect=lambda gateway,**kw:gateway.provider), \
                 patch('stbench.harness.engine.evaluate',side_effect=evaluate):
                campaign.run_stage(cfg,Path(d),stage,{m['id']:'chat' for m in cfg['models']})
            folder=Path(d)/(stage if stage!='develop' else 'develop_round_1')
            records=[RunRecord.load(p) for p in folder.glob('*/*.json') if not p.name.endswith(('.timing.json','.openplc.json'))]
            self.assertTrue(all(r.solved for r in records),[(r.pid,r.error,r.stop_reason) for r in records if not r.solved][:3])
            self.assertTrue(all(len(r.attempts)==2 for r in records))
            self.assertTrue(all(r.request_window_seconds==450 for r in records))
            self.assertEqual(calls.count(False),len(records));self.assertEqual(calls.count(True),len(records))
            state=json.loads(Path(cfg['budget_ledger_path']).read_text())
            self.assertAlmostEqual(state['spent_cny'],initial_spend+.002*len(records),places=5)
            return len(records)

    def test_development_repair_is_not_limited_to_the_first_request_input_bound(self):
        self.assertEqual(self.simulate('develop',0),12)

    def test_formal_coverage_finishes_before_deferred_repairs_are_abandoned(self):
        self.assertEqual(self.simulate('final',63.5),140)

    def test_prior_platform_and_framework_time_counts_towards_the_task_limit(self):
        p=Problem.from_dict(dict(pid='elapsed',source='selfmade',title='elapsed',difficulty='easy',requirements='true',
            variables=[dict(name='out',data_type='BOOL',direction='output')],
            test_cases=[dict(tc_id='case',inputs={},expected={'out':True})]))
        provider=SimpleNamespace(name='mock',model='local-only',timeout=420,generate=Mock(side_effect=AssertionError('No time remains')))
        r=solve_problem(p,Solver(provider,task_seconds=1,model_check=False),active_elapsed_before=2)
        provider.generate.assert_not_called();self.assertEqual(r.stop_reason,'task_timeout');self.assertEqual(r.tests_total,1)


if __name__=='__main__':unittest.main()

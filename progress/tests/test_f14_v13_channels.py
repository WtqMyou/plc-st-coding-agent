"""Exercise metered generation -> exact patch -> independent evaluation without network."""
from concurrent.futures import ThreadPoolExecutor
import json
from test_f14_v13_budget import BudgetTests
import f14_v13_core as s
import f14_v13_budget as b
from full_r8b_transport import MeteredProvider

BAD='FUNCTION_BLOCK FB VAR_OUTPUT x:BOOL;END_VAR x:=FALSE;END_FUNCTION_BLOCK'
GOOD=BAD.replace('FALSE','TRUE')

class Channels(BudgetTests):
    def test_compile_functional_and_formal_repair_routes_exactly_once(self):
        cfg=s.config();jobs=[];pids=list(s.tasks())[:3]
        for pid in pids:
            job=dict(pid=pid,phase='full',framework='custom',model_id='deepseek-v4pro',condition='custom_deepseek-v4pro',job_id='custom_deepseek-v4pro/'+pid,first_upper_cny=2,repair_upper_cny=2)
            job['initial_user_sha256']=s.hashlib.sha256(s.messages(job)[1]['content'].encode()).hexdigest();jobs.append(job)
        (self.root/'study_plan.json').write_text('{}')
        state=s.load(self.path);state['active_experiment_scope']=dict(conditions=['custom_deepseek-v4pro']);s.atomic_json(self.path,state)
        co=b.Coordinator(self.path,dict(sha256='plan',jobs=jobs),baseline=self.before)
        markers={pids[0]:'PUBLIC_COMPILER_DIAGNOSTIC',pids[1]:'OBSERVED_FUNCTIONAL_TRACE',pids[2]:'CONFIRMED_BOUNDED_VIOLATION'}
        def factory(spec,budget,**kwargs):
            def sender(*args):
                text=BAD if budget.context['candidate_index']==0 else json.dumps(dict(edits=[dict(old='x:=FALSE;',new='x:=TRUE;')]))
                return dict(model=spec['model'],status='completed',usage=dict(input_tokens=0,output_tokens=0),output=[dict(type='message',content=[dict(type='output_text',text=text)])])
            return MeteredProvider(spec,budget,**kwargs,offline=True,sender=sender)
        def evaluate(code,pid,*args):
            repaired=code==GOOD;compiles=repaired or pid!=pids[0];functional=repaired or pid==pids[2]
            return dict(result=dict(compiles=compiles,compile_errors=[] if compiles else [dict(code='E_UNDECLARED')],tests_total=1,tests_passed=int(functional),
                platform_results=dict(codesys=dict(status='passed' if compiles else 'failed'))),verification_status='bounded_pass' if repaired else 'violated' if pid==pids[2] else 'not_run',feedback=markers[pid],complete_code=True,shared_tool_error=False)
        with ThreadPoolExecutor(max_workers=3) as pool:
            records=list(pool.map(lambda job:s.generate_job(cfg,self.root,{},job,co.view(job['job_id']),{},factory=factory,evaluator=evaluate),jobs))
        self.assertEqual(len(co.read()['events'])-3,6)
        for job,record in zip(jobs,records):
            self.assertEqual(len(record['attempts']),2);self.assertTrue(record['job_done']);self.assertEqual(record['attempts'][-1]['code'],GOOD)
            trace=s.load(self.root/'jobs'/job['condition']/(job['pid']+'.request_02.json'))
            self.assertIn(markers[job['pid']],json.dumps(trace));self.assertIn('REPAIR OUTPUT MODE',json.dumps(trace))
            self.assertNotIn('"expected":',json.dumps(trace))

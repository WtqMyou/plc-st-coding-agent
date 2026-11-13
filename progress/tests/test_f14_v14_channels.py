"""Real isolated CLI + mock upstream: both models and all three repair feedback types."""
from concurrent.futures import ThreadPoolExecutor
import json
from test_f14_v14_budget import BudgetTests
import f14_v14_core as s
import f14_v14_budget as b
from full_r8b_transport import MeteredProvider

BAD='FUNCTION_BLOCK FB VAR_OUTPUT x:BOOL;END_VAR x:=FALSE;END_FUNCTION_BLOCK'
GOOD=BAD.replace('FALSE','TRUE')

class Channels(BudgetTests):
    def test_four_arms_forward_three_feedback_types_and_apply_model_edits(self):
        cfg=s.config();jobs=[];pids=list(s.tasks())[:3]
        for framework,mid in s.old.ARMS:
            for pid in pids:
                condition=framework+'_'+mid
                job=dict(pid=pid,phase='full',framework=framework,model_id=mid,condition=condition,job_id=condition+'/'+pid,first_upper_cny=2,repair_upper_cny=2)
                job['initial_user_sha256']=s.hashlib.sha256(s.messages(job)[1]['content'].encode()).hexdigest();jobs.append(job)
        (self.root/'study_plan.json').write_text('{}')
        state=s.load(self.path);state['active_experiment_scope']=dict(conditions=sorted({j['condition'] for j in jobs}));s.atomic_json(self.path,state)
        co=b.Coordinator(self.path,dict(sha256='plan',jobs=jobs),baseline=self.before)
        markers={pids[0]:'PUBLIC_COMPILER_DIAGNOSTIC',pids[1]:'OBSERVED_FUNCTIONAL_TRACE',pids[2]:'CONFIRMED_BOUNDED_VIOLATION'}
        def factory(spec,budget,**kwargs):
            def sender(*args):
                text=BAD if budget.context['candidate_index']==0 else json.dumps(dict(edits=[dict(old='x:=FALSE;',new='x:=TRUE;')]))
                if spec['generation_protocol']=='chat':return dict(model=spec['model'],usage=dict(prompt_tokens=0,completion_tokens=0),choices=[dict(finish_reason='stop',message=dict(content=text))])
                return dict(model=spec['model'],status='completed',usage=dict(input_tokens=0,output_tokens=0),output=[dict(type='message',content=[dict(type='output_text',text=text)])])
            return MeteredProvider(spec,budget,**kwargs,offline=True,sender=sender)
        def evaluate(code,pid,*args):
            repaired=code==GOOD;compiles=repaired or pid!=pids[0];functional=repaired or pid==pids[2]
            return dict(result=dict(compiles=compiles,compile_errors=[] if compiles else [dict(code='E_UNDECLARED')],tests_total=1,tests_passed=int(functional),
                platform_results=dict(codesys=dict(status='passed' if compiles else 'failed'))),verification_status='bounded_pass' if repaired else 'violated' if pid==pids[2] else 'not_run',feedback=markers[pid],complete_code=True,shared_tool_error=False)
        with ThreadPoolExecutor(max_workers=8) as pool:
            records=list(pool.map(lambda job:s.generate_job(cfg,self.root,{},job,co.view(job['job_id']),{},factory=factory,evaluator=evaluate),jobs))
        self.assertEqual(len(co.read()['events'])-3,24)
        for job,record in zip(jobs,records):
            self.assertTrue(record['job_done']);self.assertEqual(len(record['attempts']),2);self.assertEqual(record['attempts'][1]['code'],GOOD)
            trace=s.load(self.root/'jobs'/job['condition']/(job['pid']+'.request_02.json'))
            self.assertIn(markers[job['pid']],json.dumps(trace));self.assertIn('REPAIR OUTPUT MODE',json.dumps(trace));self.assertNotIn('"expected":',json.dumps(trace))

    def test_plan_excludes_all_imported_jobs_from_new_schedule(self):
        root=self.root/'plan';root.mkdir();cfg=dict(s.config(),campaign_root=str(root),budget_ledger_path=str(self.path))
        routes=[]
        for pid in s.tasks():
            for framework,mid in s.old.ARMS:routes.append(dict(job_id=framework+'_'+mid+'/'+pid,first_upper_cny=.1,repair_upper_cny=.1))
        s.atomic_json(root/'offline_routes.json',dict(completed=True,rows=routes))
        plan=s.build_plan(cfg,s.load(self.path))
        self.assertEqual(len(plan['jobs']),120);self.assertEqual(len(plan['imported_jobs']),20)
        new={j['job_id'] for j in plan['jobs']};old={j['job_id'] for j in plan['imported_jobs']}
        self.assertFalse(new&old);self.assertEqual(len(new|old),140)

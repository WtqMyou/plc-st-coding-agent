"""Free concurrency, budget and judge calibration; never use the live ledger."""
from concurrent.futures import ThreadPoolExecutor
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import f14_v3_core as s
import f14_v3_budget as b
from full_r8b_transport import MeteredProvider
from stbench.providers.base import ProviderError

GOOD='FUNCTION_BLOCK FB VAR_OUTPUT x:BOOL;END_VAR x:=TRUE;END_FUNCTION_BLOCK'
BAD=GOOD.replace('TRUE','FALSE')

class FormattingTests(unittest.TestCase):
    def test_comments_strings_idempotence_and_no_type_changes(self):
        code="FUNCTION_BLOCK FB VAR a:LTIME;u:UINT;v:VARIANT;msg:STRING:='END_IF';END_VAR (* END_TYPE *) IF TRUE THEN msg:='END_CASE';END_IF END_FUNCTION_BLOCK"
        fixed,edits=s.normalize(code)
        self.assertEqual(len(edits),1);self.assertIn('END_IF;',fixed);self.assertIn("msg:='END_CASE';",fixed)
        self.assertIn('a:LTIME;u:UINT;v:VARIANT;',fixed);self.assertEqual(s.normalize(fixed),(fixed,[]))
    def test_never_adds_missing_end_or_changes_nesting(self):
        code='IF a THEN x:=1;ELSE (* nested *) IF b THEN x:=2;END_IF END_IF'
        fixed,edits=s.normalize(code);self.assertEqual(len(edits),2);self.assertIn('ELSE (* nested *) IF',fixed)
        self.assertNotIn('ELSIF',fixed);self.assertNotIn('END_FUNCTION_BLOCK',fixed)
    def test_all_references_and_private_rename_controls(self):
        root=s.REPO/'progress/evidence/f14_v3_preflight_20261112'
        a=s.load(root/'semicolon_reference_replay.json');c=s.load(root/'judge_calibration.json')
        self.assertEqual(a['passed'],946);self.assertEqual(c['negative_controls'],35);self.assertEqual(c['private_rename_regressions'],[])
    def test_canonical_interface_contains_no_solution_or_expectations(self):
        for pid,task in s.tasks().items():
            messages=s.messages(dict(pid=pid));system=messages[0]['content']
            self.assertNotIn('test_cases',system);self.assertNotIn('expected',system)
            self.assertEqual(messages[1]['content'],s.load(s.RELEASE/'agent_inputs.json')[pid]['user'])
            for variable in task['variables']:self.assertIn(variable['name'],system)
    def test_safe_feedback_has_inputs_and_actual_without_expectations(self):
        pid='public-easy-01';source=(s.RELEASE/'datasets/public/tests'/ (pid+'.reference.st')).read_text(encoding='utf-8')
        source=source.replace('END_FUNCTION_BLOCK','Pump_Motor:=FALSE;END_FUNCTION_BLOCK')
        result=s.run_stage(source,pid,'functional',30)
        text=result['feedback'];self.assertIn('input_trace',text);self.assertIn('observed_outputs',text)
        self.assertNotIn('"expected":',text);self.assertNotIn('"note":',text);self.assertNotIn('期望 True',text)

class BudgetTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        self.patch_h=patch.object(b,'HISTORY',3);self.patch_b=patch.object(b,'BASELINE',10)
        self.patch_h.start();self.patch_b.start();self.addCleanup(self.patch_h.stop);self.addCleanup(self.patch_b.stop)
        self.path=self.root/'ledger.json';self.before=dict(version=3,limit_cny=190,spent_cny=10,events=[dict(phase='history') for _ in range(3)],recoveries=[],historic_authorization=dict(keep=True))
        state=copy.deepcopy(self.before);state.update(limit_cny=210,halted='',f14_v3_authorization=dict(study_plan_sha256='plan',total_cap_cny=210))
        s.atomic_json(self.path,state)
        self.jobs=[dict(job_id='arm/task'+str(i),first_upper_cny=.6,repair_upper_cny=.9) for i in range(40)]
        self.plan=dict(sha256='plan',jobs=self.jobs);self.co=b.Coordinator(self.path,self.plan,baseline=self.before)
    def view(self,index,attempt=0):
        job=self.jobs[index]['job_id'];view=self.co.view(job);view.context=dict(job_id=job,candidate_index=attempt);return view
    def test_8_concurrent_reservations_and_settlements_are_exact(self):
        barrier=threading.Barrier(8)
        def run(i):
            view=self.view(i);barrier.wait();index=view.reserve(.4);time.sleep(.02);view.settle(index,.1,metadata=dict(model='mock'));self.co.finish(view.job_id)
        with ThreadPoolExecutor(max_workers=8) as pool:list(pool.map(run,range(8)))
        ledger=self.co.read();self.assertEqual(len(ledger['events']),11);self.assertEqual(ledger['spent_cny'],10.8)
        self.assertEqual(ledger['events'][:3],self.before['events'])
    def test_protected_future_costs_block_before_sending(self):
        self.co.pending['huge']={0:s.money(199)};before=self.path.read_bytes()
        with self.assertRaises(ProviderError):self.view(0).reserve(.4)
        self.assertEqual(before,self.path.read_bytes())
    def test_duplicate_and_third_candidate_rejected(self):
        view=self.view(0);view.reserve(.4)
        with self.assertRaises(ProviderError):view.reserve(.4)
        with self.assertRaises(AssertionError):self.view(1,2).reserve(.1)
    def test_halt_blocks_new_sends_but_other_inflight_receipt_settles(self):
        a=self.view(0);c=self.view(1);a.reserve(.4);index=c.reserve(.4)
        a.halt('unknown',details=dict(category='mock'))
        with self.assertRaises(b.CampaignStopped):self.view(2).reserve(.1)
        c.settle(index,.1,metadata=dict(model='mock'))
        ledger=self.co.read(allow_halted=True);self.assertEqual(ledger['events'][3]['status'],'reserved');self.assertEqual(ledger['events'][4]['status'],'settled')
        self.assertEqual(ledger['spent_cny'],10.5);self.assertEqual(ledger['halted'],'unknown')
    def test_no_shared_mutable_request_context(self):
        a,c=self.view(0),self.view(1);self.assertIsNot(a.context,c.context)
        ai=a.reserve(.4);ci=c.reserve(.3);l=self.co.read();self.assertNotEqual(l['events'][ai]['request']['job_id'],l['events'][ci]['request']['job_id'])
    def test_restored_coordinator_cannot_repeat_a_reserved_request(self):
        self.view(0).reserve(.4);restored=b.Coordinator(self.path,self.plan,baseline=self.before)
        view=restored.view(self.jobs[0]['job_id']);view.context=dict(job_id=view.job_id,candidate_index=0)
        with self.assertRaises(ProviderError):view.reserve(.4)
    def test_authorization_retains_old_unknown_fee_and_is_idempotent(self):
        original=copy.deepcopy(self.before)
        original.update(halted='Unconfirmed upstream result; reservation retained',halt_details=dict(category='request_timeout'))
        original['events'][-1]=dict(request_id='cb1122ed17f74e54bdd58ab2020041e1',status='reserved',reserved_cny=.121743,phase='f14_v2_public_20261112')
        s.atomic_json(self.path,original);before=self.path.read_bytes()
        b.authorize(self.path,before,'plan','proof');state=s.load(self.path)
        self.assertEqual(state['events'],original['events']);self.assertEqual(state['spent_cny'],10)
        self.assertEqual(state['limit_cny'],210);self.assertEqual(state['events'][-1]['status'],'reserved')
        raw=self.path.read_bytes();b.authorize(self.path,before,'plan','proof');self.assertEqual(self.path.read_bytes(),raw)

class ControllerTests(BudgetTests):
    def test_parallel_model_calls_and_job_artifacts(self):
        cfg=s.config();active=0;peak=0;lock=threading.Lock();seen=[]
        (self.root/'study_plan.json').write_text('{}')
        jobs=[]
        for i,pid in enumerate(list(s.tasks())[:8]):
            condition='custom_deepseek-v4pro';job=dict(pid=pid,framework='custom',model_id='deepseek-v4pro',condition=condition,job_id=condition+'/'+pid,first_upper_cny=2,repair_upper_cny=2)
            job['initial_user_sha256']=s.hashlib.sha256(s.messages(job)[1]['content'].encode()).hexdigest();jobs.append(job)
        state=s.load(self.path);state['events']=state['events'][:3];s.atomic_json(self.path,state)
        co=b.Coordinator(self.path,dict(sha256='plan',jobs=jobs),baseline=self.before)
        def factory(spec,budget,**kwargs):
            def sender(*args):
                nonlocal active,peak
                with lock:active+=1;peak=max(peak,active);seen.append(budget.job_id)
                time.sleep(.08)
                with lock:active-=1
                return dict(model=spec['model'],status='completed',usage=dict(input_tokens=0,output_tokens=0),output=[dict(type='message',content=[dict(type='output_text',text=GOOD)])])
            return MeteredProvider(spec,budget,**kwargs,offline=True,sender=sender)
        def evaluate(*args):
            return dict(result=dict(compiles=True,compile_errors=[],tests_total=1,tests_passed=1,model_check={},platform_results=dict(codesys=dict(status='passed'))),verification_status='truncated',feedback='ok',complete_code=True,shared_tool_error=False)
        with ThreadPoolExecutor(max_workers=8) as pool:
            results=list(pool.map(lambda job:s.generate_job(cfg,self.root,{},job,co.view(job['job_id']),{},factory=factory,evaluator=evaluate),jobs))
        self.assertGreaterEqual(peak,2);self.assertLessEqual(peak,4);self.assertEqual(len(seen),8);self.assertTrue(all(r['job_done'] and len(r['attempts'])==1 for r in results))
        self.assertEqual(len(list((self.root/'jobs').glob('*/*.request_01.json'))),8)
    def test_eight_parallel_requests_cover_both_models_and_real_cli(self):
        cfg=s.config();jobs=[];barrier=threading.Barrier(8);seen=[];lock=threading.Lock();counts={}
        (self.root/'study_plan.json').write_text('{}')
        for framework,mid in s.old.ARMS:
            for pid in list(s.tasks())[:2]:
                condition=framework+'_'+mid;job=dict(pid=pid,framework=framework,model_id=mid,condition=condition,job_id=condition+'/'+pid,first_upper_cny=2,repair_upper_cny=2)
                job['initial_user_sha256']=s.hashlib.sha256(s.messages(job)[1]['content'].encode()).hexdigest();jobs.append(job)
        co=b.Coordinator(self.path,dict(sha256='plan',jobs=jobs),baseline=self.before)
        def factory(spec,budget,**kwargs):
            def sender(*args):
                with lock:
                    seen.append(budget.job_id);counts[budget.job_id]=counts.get(budget.job_id,0)+1;attempt=counts[budget.job_id]
                barrier.wait(timeout=40)
                code=BAD if attempt==1 else GOOD
                if spec['generation_protocol']=='chat':return dict(model=spec['model'],usage=dict(prompt_tokens=0,completion_tokens=0),choices=[dict(finish_reason='stop',message=dict(content=code))])
                return dict(model=spec['model'],status='completed',usage=dict(input_tokens=0,output_tokens=0),output=[dict(type='message',content=[dict(type='output_text',text=code)])])
            return MeteredProvider(spec,budget,**kwargs,offline=True,sender=sender)
        def evaluate(code,*args):return dict(result=dict(compiles=True,compile_errors=[],tests_total=1,tests_passed=int(code==GOOD),platform_results=dict(codesys=dict(status='passed'))),verification_status='truncated',feedback='Observed functional mismatch; no hidden expected values.',complete_code=True,shared_tool_error=False)
        with ThreadPoolExecutor(max_workers=8) as pool:
            results=list(pool.map(lambda job:s.generate_job(cfg,self.root,{},job,co.view(job['job_id']),{},factory=factory,evaluator=evaluate),jobs))
        self.assertEqual(len(set(seen)),8);self.assertTrue(all(r['job_done'] and len(r['attempts'])==2 for r in results))
        self.assertEqual(len(co.read()['events'])-3,16)

if __name__=='__main__':unittest.main()

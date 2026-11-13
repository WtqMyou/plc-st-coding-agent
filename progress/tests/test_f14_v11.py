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
import f14_v11_core as s
import f14_v11_budget as b
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
        self.path=self.root/'ledger.json';self.before=dict(version=3,limit_cny=420,spent_cny=10,events=[dict(phase='history') for _ in range(3)],recoveries=[],historic_authorization=dict(keep=True))
        state=copy.deepcopy(self.before);state.update(limit_cny=420,halted='',f14_v11_authorization=dict(study_plan_sha256='plan',total_cap_cny=420))
        s.atomic_json(self.path,state)
        self.jobs=[dict(job_id='arm/task'+str(i),first_upper_cny=.1,repair_upper_cny=.1) for i in range(141)]
        self.plan=dict(sha256='plan',jobs=self.jobs);self.co=b.Coordinator(self.path,self.plan,baseline=self.before)
        for bounds in self.co.bounds.values():
            for idx in bounds:bounds[idx]=s.money(.9)
        self.co.pending={k:dict(v) for k,v in self.co.bounds.items()}
        for key in list(self.co.pending)[40:]:self.co.pending[key]={i:s.money(0) for i in range(4)}
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
        self.co.pending['huge']={0:s.money(419)};before=self.path.read_bytes()
        with self.assertRaises(ProviderError):self.view(0).reserve(.4)
        self.assertEqual(before,self.path.read_bytes())
    def test_duplicate_and_fifth_candidate_rejected(self):
        view=self.view(0);view.reserve(.4)
        with self.assertRaises(ProviderError):view.reserve(.4)
        with self.assertRaises(AssertionError):self.view(1,4).reserve(.1)
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
    def test_maximum_320_requests_blocks_the_321st_before_charging(self):
        for index in range(80):
            for attempt in range(4):self.view(index,attempt).reserve(0)
        before=self.path.read_bytes()
        with self.assertRaises(ProviderError):self.view(80).reserve(0)
        self.assertEqual(before,self.path.read_bytes())
    def test_authorization_retains_old_unknown_fee_and_is_idempotent(self):
        original=copy.deepcopy(self.before)
        original.update(halted='')
        original['events'][-1]=dict(request_id='historical_unknown',status='reserved',reserved_cny=.121743,phase='previous_batch')
        s.atomic_json(self.path,original);before=self.path.read_bytes()
        b.authorize(self.path,before,'plan','proof');state=s.load(self.path)
        self.assertEqual(state['events'],original['events']);self.assertEqual(state['spent_cny'],10)
        self.assertEqual(state['limit_cny'],420);self.assertEqual(state['events'][-1]['status'],'reserved')
        raw=self.path.read_bytes();b.authorize(self.path,before,'plan','proof');self.assertEqual(self.path.read_bytes(),raw)

class ControllerTests(BudgetTests):
    def test_parallel_model_calls_and_job_artifacts(self):
        cfg=s.config();active=0;peak=0;lock=threading.Lock();seen=[]
        (self.root/'study_plan.json').write_text('{}')
        jobs=[]
        for i,pid in enumerate(list(s.tasks())[:6]):
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
        self.assertGreaterEqual(peak,2);self.assertLessEqual(peak,8);self.assertEqual(len(seen),6);self.assertTrue(all(r['job_done'] and len(r['attempts'])==1 for r in results))
        self.assertEqual(len(list((self.root/'jobs').glob('*/*.request_01.json'))),6)
    def test_eight_parallel_requests_cover_both_models_and_real_cli(self):
        cfg=s.config();jobs=[];barrier=threading.Barrier(4);seen=[];lock=threading.Lock();counts={}
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

class RepairFeedbackTests(BudgetTests):
    def test_all_four_arms_forward_compile_functional_and_formal_feedback(self):
        import f14_v10_core  # Historical imports must not replace V11's uniquely named policy.
        cfg=s.config();jobs=[];pids=list(s.tasks())[:3]
        for framework,mid in s.old.ARMS:
            for pid in pids:
                condition=framework+'_'+mid
                job=dict(pid=pid,framework=framework,model_id=mid,condition=condition,job_id=condition+'/'+pid,first_upper_cny=2,repair_upper_cny=2)
                job['initial_user_sha256']=s.hashlib.sha256(s.messages(job)[1]['content'].encode()).hexdigest();jobs.append(job)
        (self.root/'study_plan.json').write_text('{}')
        co=b.Coordinator(self.path,dict(sha256='plan',jobs=jobs),baseline=self.before)
        markers={pids[0]:'PUBLIC_COMPILER_DIAGNOSTIC',pids[1]:'OBSERVED_FUNCTIONAL_TRACE',pids[2]:'CONFIRMED_BOUNDED_VIOLATION'}
        def factory(spec,budget,**kwargs):
            def sender(*args):
                code=BAD if budget.context['candidate_index']==0 else GOOD
                if spec['generation_protocol']=='chat':return dict(model=spec['model'],usage=dict(prompt_tokens=0,completion_tokens=0),choices=[dict(finish_reason='stop',message=dict(content=code))])
                return dict(model=spec['model'],status='completed',usage=dict(input_tokens=0,output_tokens=0),output=[dict(type='message',content=[dict(type='output_text',text=code)])])
            return MeteredProvider(spec,budget,**kwargs,offline=True,sender=sender)
        def evaluate(code,pid,*args):
            repaired=code==GOOD;compiles=repaired or pid!=pids[0]
            functional=repaired or pid==pids[2]
            return dict(result=dict(compiles=compiles,compile_errors=[] if compiles else [dict(code='E_UNDECLARED')],
                tests_total=1,tests_passed=int(functional),platform_results=dict(codesys=dict(status='passed' if compiles else 'failed'))),
                verification_status='bounded_pass' if repaired else 'violated' if pid==pids[2] else 'not_run',
                feedback=markers[pid],complete_code=True,shared_tool_error=False)
        with ThreadPoolExecutor(max_workers=4) as pool:
            records=list(pool.map(lambda job:s.generate_job(cfg,self.root,{},job,co.view(job['job_id']),{},factory=factory,evaluator=evaluate),jobs))
        self.assertEqual(len(co.read()['events'])-3,24)
        for job,record in zip(jobs,records):
            self.assertEqual(len(record['attempts']),2);self.assertTrue(record['job_done'])
            trace=s.load(self.root/'jobs'/job['condition']/(job['pid']+'.request_02.json'))
            self.assertIn(markers[job['pid']],json.dumps(trace,ensure_ascii=False))
            self.assertIn('The selected candidate reflects',json.dumps(trace,ensure_ascii=False))
            self.assertNotIn('"expected":',json.dumps(trace,ensure_ascii=False))

class SemanticGateTests(unittest.TestCase):
    def probe(self,source,scans,outputs):
        request=dict(source=source,scans=scans,outputs=outputs)
        process=subprocess.run([sys.executable,'-B','-X','utf8',str(s.CONFIG.parent/'runtime_probe.py')],
            input=json.dumps(request),capture_output=True,text=True,encoding='utf-8',timeout=15)
        self.assertEqual(process.returncode,0,process.stderr)
        result=json.loads(process.stdout);self.assertTrue(result['ok'],result)
        return result['scans']
    def test_anonymous_enum_state_retention_and_explicit_initializer(self):
        source='FUNCTION_BLOCK FB VAR_INPUT go:BOOL;END_VAR VAR_OUTPUT x:INT;END_VAR VAR state:(IDLE,ACTIVE):=ACTIVE;END_VAR IF go THEN state:=IDLE;END_IF;CASE state OF IDLE:x:=3;ACTIVE:x:=7;END_CASE;END_FUNCTION_BLOCK'
        self.assertEqual(self.probe(source,[{},dict(go=True),dict(go=False)],['x']),[dict(x=7),dict(x=3),dict(x=3)])
    def test_nested_case_and_if_do_not_consume_outer_label(self):
        source='FUNCTION_BLOCK FB VAR_INPUT mode:INT;go:BOOL;END_VAR VAR_OUTPUT x:INT;END_VAR CASE mode OF 1:IF go THEN CASE mode OF 1:x:=7;2:x:=8;END_CASE;END_IF;2:x:=9;ELSE x:=0;END_CASE;END_FUNCTION_BLOCK'
        self.assertEqual(self.probe(source,[dict(mode=1,go=True),dict(mode=2),dict(mode=3)],['x']),[dict(x=7),dict(x=9),dict(x=0)])
    def test_recursive_struct_field_typo_is_an_interface_error(self):
        pid='public-medium-01';path,=s.RELEASE.glob('datasets/*/tests/'+pid+'.reference.st')
        source=path.read_text(encoding='utf-8');bad=source.replace('RunComd','RunCmd')
        self.assertNotEqual(source,bad)
        good=s.run_stage(source,pid,'static',30);result=s.run_stage(bad,pid,'static',30)
        self.assertTrue(good['result']['compiles'],good)
        self.assertTrue(any(d['code']=='E_INTERFACE_FIELD' for d in result['result']['compile_errors']),result)
    def test_public_clauses_are_exact_substrings_and_original_user_is_verbatim(self):
        from v11_contracts import clauses
        users=s.load(s.RELEASE/'agent_inputs.json')
        for pid in s.tasks():
            original=users[pid]['user'];messages=s.messages(dict(pid=pid))
            self.assertEqual(messages[1]['content'],original)
            self.assertTrue(all(row['text'] in original for row in clauses(original)))
            self.assertIn('ENGINEERING_CONTRACT',messages[0]['content'])
            self.assertNotIn('"test_cases"',messages[0]['content'])
            self.assertNotIn('__spec_',messages[0]['content'])
    def test_unknown_charge_halt_cannot_be_cleared_by_new_authorization(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'ledger.json'
            state=dict(version=3,limit_cny=420,spent_cny=b.BASELINE,events=[{}]*b.HISTORY,halted='unknown')
            s.atomic_json(path,state);before=path.read_bytes()
            with self.assertRaises(AssertionError):b.authorize(path,before,'plan','proof')
            self.assertEqual(path.read_bytes(),before)

class V6NativeSemantics(SemanticGateTests):
    def test_struct_and_nested_array_assignments_copy_values(self):
        source='TYPE ST_A:STRUCT ident:INT;items:ARRAY[0..1] OF INT;END_STRUCT END_TYPE FUNCTION_BLOCK FB VAR_OUTPUT result:INT;END_VAR VAR originalRecord,copiedRecord:ST_A;END_VAR originalRecord.ident:=7;originalRecord.items[0]:=11;copiedRecord:=originalRecord;copiedRecord.ident:=0;copiedRecord.items[0]:=0;result:=originalRecord.ident+originalRecord.items[0];END_FUNCTION_BLOCK'
        self.assertEqual(self.probe(source,[{}],['result']),[dict(result=18)])
    def test_array_copy_and_reference_field_writes_are_independent(self):
        source='FUNCTION_BLOCK FB VAR_OUTPUT result:INT;END_VAR VAR aa,bb:ARRAY[0..1] OF INT;END_VAR aa[0]:=3;bb:=aa;bb[0]:=0;result:=aa[0];END_FUNCTION_BLOCK'
        self.assertEqual(self.probe(source,[{}],['result']),[dict(result=3)])
    def test_byte_index_type_is_numeric_and_zero_based(self):
        source="FUNCTION_BLOCK FB VAR_INPUT txt:STRING(8);END_VAR VAR_OUTPUT first:INT;dot:INT;last:INT;END_VAR VAR ch:BYTE;END_VAR ch:=txt[0];first:=BYTE_TO_INT(ch);dot:=TO_INT(TO_BYTE(txt[1]));last:=BYTE_TO_INT(txt[2]);END_FUNCTION_BLOCK"
        self.assertEqual(self.probe(source,[dict(txt='1.')],['first','dot','last']),[dict(first=49,dot=46,last=0)])
    def test_generic_real_precision(self):
        source='FUNCTION_BLOCK FB VAR_OUTPUT wide:LREAL;narrow:REAL;END_VAR wide:=TO_LREAL(DINT#16777217);narrow:=TO_REAL(DINT#16777217);END_FUNCTION_BLOCK'
        self.assertEqual(self.probe(source,[{}],['wide','narrow']),[dict(wide=16777217.0,narrow=16777216.0)])
    def test_complete_sequence_feedback_preserves_original_prefix(self):
        pid='public-hard-03';path,=s.RELEASE.glob('datasets/*/tests/'+pid+'.reference.st')
        source=path.read_text(encoding='utf-8').replace('END_FUNCTION_BLOCK','recipeAdded:=FALSE;END_FUNCTION_BLOCK')
        result=s.run_stage(source,pid,'functional',30);text=result['feedback']
        self.assertIn('"prefix_omitted": false',text)
        self.assertNotIn('"expected":',text);self.assertNotIn('"note":',text)
        if '"mode": "sequence"' in text:self.assertIn('h03-1',text)
    def test_declared_latch_contract_executes_public_input_traces(self):
        pid='public-easy-01';path,=s.RELEASE.glob('datasets/*/tests/'+pid+'.reference.st')
        source=path.read_text(encoding='utf-8')
        rule='(* CONTRACT_RULES [{"kind":"hold_until_reset","output":"Pump_Motor","set_input":"bottleSensor","reset_input":"finishedButton"}] *)'
        source=rule+source.replace('END_FUNCTION_BLOCK','IF cleaningConfirmButton THEN Pump_Motor:=FALSE;END_IF;END_FUNCTION_BLOCK')
        result=s.run_stage(source,pid,'functional',30)
        checks=result['result']['evidence_metadata']['declared_contract_check']
        self.assertEqual(checks['supported'],1);self.assertTrue(checks['violations'])
        self.assertIn('Candidate-declared contract check',result['feedback'])

class FourCandidateController(BudgetTests):
    def test_oversized_repair_stops_job_without_an_extra_fee_or_fabricated_attempt(self):
        cfg=s.config();pid=next(iter(s.tasks()));condition='custom_deepseek-v4pro'
        job=dict(pid=pid,framework='custom',model_id='deepseek-v4pro',condition=condition,job_id=condition+'/'+pid,first_upper_cny=2,repair_upper_cny=2)
        job['initial_user_sha256']=s.hashlib.sha256(s.messages(job)[1]['content'].encode()).hexdigest()
        (self.root/'study_plan.json').write_text('{}')
        co=b.Coordinator(self.path,dict(sha256='plan',jobs=[job]),baseline=self.before)
        sends=[]
        def factory(spec,budget,**kwargs):
            def sender(*args):
                sends.append(1)
                return dict(model=spec['model'],status='completed',usage=dict(input_tokens=0,output_tokens=0),output=[dict(type='message',content=[dict(type='output_text',text=BAD)])])
            return MeteredProvider(spec,budget,**kwargs,offline=True,sender=sender)
        def evaluate(*args):return dict(result=dict(compiles=True,compile_errors=[],tests_total=1,tests_passed=0,platform_results=dict(codesys=dict(status='passed'))),verification_status='not_run',feedback='x'*2000000,complete_code=True,shared_tool_error=False)
        record=s.generate_job(cfg,self.root,{},job,co.view(job['job_id']),{},factory=factory,evaluator=evaluate)
        self.assertTrue(record['job_done']);self.assertEqual(record['stop_reason'],'repair_input_limit_before_send')
        self.assertEqual(len(record['attempts']),1);self.assertEqual(len(sends),1);self.assertEqual(len(co.read()['events'])-3,1)
    def test_repeating_any_prior_candidate_stops_before_a_fourth_request(self):
        cfg=s.config();pid=next(iter(s.tasks()));condition='custom_deepseek-v4pro'
        job=dict(pid=pid,framework='custom',model_id='deepseek-v4pro',condition=condition,job_id=condition+'/'+pid,first_upper_cny=2,repair_upper_cny=2)
        job['initial_user_sha256']=s.hashlib.sha256(s.messages(job)[1]['content'].encode()).hexdigest()
        (self.root/'study_plan.json').write_text('{}')
        co=b.Coordinator(self.path,dict(sha256='plan',jobs=[job]),baseline=self.before)
        codes=['FUNCTION_BLOCK FB VAR_OUTPUT x:INT;END_VAR x:='+str(i)+';END_FUNCTION_BLOCK' for i in range(2)]
        def factory(spec,budget,**kwargs):
            def sender(*args):
                code=codes[1 if budget.context['candidate_index']==1 else 0]
                return dict(model=spec['model'],status='completed',usage=dict(input_tokens=0,output_tokens=0),output=[dict(type='message',content=[dict(type='output_text',text=code)])])
            return MeteredProvider(spec,budget,**kwargs,offline=True,sender=sender)
        def evaluate(code,*args):return dict(result=dict(compiles=True,compile_errors=[],tests_total=2,tests_passed=codes.index(code),platform_results=dict(codesys=dict(status='passed'))),verification_status='not_run',feedback='Observed public behavior still differs.',complete_code=True,shared_tool_error=False)
        record=s.generate_job(cfg,self.root,{},job,co.view(job['job_id']),{},factory=factory,evaluator=evaluate)
        self.assertTrue(record['job_done']);self.assertEqual(record['stop_reason'],'repeated_candidate')
        self.assertEqual(len(record['attempts']),3);self.assertEqual(record['best_attempt'],1)
        self.assertEqual(len(co.read()['events'])-3,3)
    def test_four_arms_cover_compile_functional_formal_then_success(self):
        cfg=s.config();pid=next(iter(s.tasks()));jobs=[]
        for framework,mid in s.old.ARMS:
            condition=framework+'_'+mid;job=dict(pid=pid,framework=framework,model_id=mid,condition=condition,job_id=condition+'/'+pid,first_upper_cny=2,repair_upper_cny=2)
            job['initial_user_sha256']=s.hashlib.sha256(s.messages(job)[1]['content'].encode()).hexdigest();jobs.append(job)
        (self.root/'study_plan.json').write_text('{}')
        co=b.Coordinator(self.path,dict(sha256='plan',jobs=jobs),baseline=self.before)
        codes=['FUNCTION_BLOCK FB VAR_OUTPUT x:INT;END_VAR x:='+str(i)+';END_FUNCTION_BLOCK' for i in range(4)]
        markers=['PUBLIC_COMPILE_FAILURE','OBSERVED_BEHAVIOR_FAILURE','CONFIRMED_FORMAL_FAILURE','SUCCESS']
        def factory(spec,budget,**kwargs):
            def sender(*args):
                code=codes[budget.context['candidate_index']]
                if spec['generation_protocol']=='chat':return dict(model=spec['model'],usage=dict(prompt_tokens=0,completion_tokens=0),choices=[dict(finish_reason='stop',message=dict(content=code))])
                return dict(model=spec['model'],status='completed',usage=dict(input_tokens=0,output_tokens=0),output=[dict(type='message',content=[dict(type='output_text',text=code)])])
            return MeteredProvider(spec,budget,**kwargs,offline=True,sender=sender)
        def evaluate(code,*args):
            index=codes.index(code);compiles=index>0;functional=index>=2
            return dict(result=dict(compiles=compiles,compile_errors=[] if compiles else [dict(code='E_UNDECLARED')],tests_total=1,tests_passed=int(functional),platform_results=dict(codesys=dict(status='passed' if compiles else 'failed'))),verification_status='bounded_pass' if index==3 else 'violated' if index==2 else 'not_run',feedback=markers[index],complete_code=True,shared_tool_error=False)
        with ThreadPoolExecutor(max_workers=4) as pool:
            records=list(pool.map(lambda job:s.generate_job(cfg,self.root,{},job,co.view(job['job_id']),{},factory=factory,evaluator=evaluate),jobs))
        self.assertEqual(len(co.read()['events'])-3,16)
        for job,record in zip(jobs,records):
            self.assertEqual(len(record['attempts']),4);self.assertTrue(record['job_done']);self.assertEqual(record['best_attempt'],3)
            for index in (1,2,3):
                trace=s.load(self.root/'jobs'/job['condition']/(job['pid']+f'.request_{index+1:02}.json'))
                self.assertIn(markers[index-1],json.dumps(trace,ensure_ascii=False))

if __name__=='__main__':unittest.main()

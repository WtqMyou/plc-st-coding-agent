"""Candidate-independent structure, repair progress, temporal feedback and output cap controls."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import unittest
import tempfile
import threading
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import f14_v11_core as s
from structure_check import check
from repair_selection import select
import f14_v11_budget as budget_module
from full_r8b_transport import MeteredProvider

class Improvements(unittest.TestCase):
    def test_16_parallel_requests_cover_all_arms_with_8_per_model_and_real_cli(self):
        with tempfile.TemporaryDirectory() as d,patch.object(budget_module,'HISTORY',0),patch.object(budget_module,'BASELINE',0):
            root=Path(d);ledger=root/'ledger.json';jobs=[];barrier=threading.Barrier(16);lock=threading.Lock();seen=[]
            s.atomic_json(root/'study_plan.json',{})
            for framework,mid in s.old.ARMS:
                for pid in list(s.tasks())[:4]:
                    condition=framework+'_'+mid;job=dict(pid=pid,framework=framework,model_id=mid,condition=condition,job_id=condition+'/'+pid,first_upper_cny=2,repair_upper_cny=2)
                    job['initial_user_sha256']=hashlib.sha256(s.messages(job)[1]['content'].encode()).hexdigest();jobs.append(job)
            before=dict(version=3,limit_cny=420,spent_cny=0,events=[],recoveries=[])
            state=dict(before,halted='',f14_v11_authorization=dict(study_plan_sha256='plan',total_cap_cny=420));s.atomic_json(ledger,state)
            co=budget_module.Coordinator(ledger,dict(sha256='plan',jobs=jobs),baseline=before)
            def factory(spec,budget,**kwargs):
                def sender(endpoint,payload,*args):
                    self.assertEqual(payload.get('max_output_tokens',payload.get('max_tokens')),24576)
                    with lock:seen.append((budget.job_id,spec['id']))
                    barrier.wait(timeout=60)
                    code='FUNCTION_BLOCK FB VAR_OUTPUT x:BOOL;END_VAR x:=TRUE;END_FUNCTION_BLOCK'
                    if spec['generation_protocol']=='chat':return dict(model=spec['model'],usage=dict(prompt_tokens=0,completion_tokens=0),choices=[dict(finish_reason='stop',message=dict(content=code))])
                    return dict(model=spec['model'],status='completed',usage=dict(input_tokens=0,output_tokens=0),output=[dict(type='message',content=[dict(type='output_text',text=code)])])
                return MeteredProvider(spec,budget,**kwargs,offline=True,sender=sender)
            def evaluate(*args):return dict(result=dict(compiles=True,compile_errors=[],tests_total=1,tests_passed=1,platform_results=dict(codesys=dict(status='passed'))),verification_status='truncated',feedback='ok',complete_code=True,shared_tool_error=False)
            with ThreadPoolExecutor(max_workers=16) as pool:
                results=list(pool.map(lambda j:s.generate_job(s.config(),root,{},j,co.view(j['job_id']),{},factory=factory,evaluator=evaluate),jobs))
            self.assertEqual(len(seen),16);self.assertEqual(sum(mid=='deepseek-v4pro' for _,mid in seen),8)
            self.assertTrue(all(r['job_done'] and len(r['attempts'])==1 for r in results));self.assertEqual(len(co.read()['events']),16)
    def test_20_public_tasks_470_cases_and_24576_output_16_workers(self):
        cfg=s.config();self.assertEqual(len(s.tasks()),20);self.assertEqual(sum(len(t['test_cases']) for t in s.tasks().values()),470)
        self.assertEqual(cfg['limits']['max_output_tokens'],24576);self.assertEqual(cfg['concurrency']['max_jobs'],16)
    def test_nested_structures_and_comments_strings(self):
        valid="FUNCTION_BLOCK FB VAR i:INT;txt:STRING;END_VAR (* IF BEGIN *) txt:='END_IF';CASE i OF 0:FOR i:=0 TO 3 DO IF i=1 THEN EXIT;END_IF;END_FOR;ELSE WHILE FALSE DO REPEAT EXIT;UNTIL TRUE END_REPEAT;END_WHILE;END_CASE;END_FUNCTION_BLOCK"
        self.assertEqual(check(valid),[])
    def test_pascal_begin_and_incorrect_closures_report_exact_causes(self):
        self.assertTrue(any('Pascal' in e['message'] for e in check('FUNCTION_BLOCK FB VAR x:INT;END_VAR BEGIN x:=1;END_FUNCTION_BLOCK')))
        errors=check('FUNCTION_BLOCK FB VAR x:INT;END_VAR IF TRUE THEN CASE x OF 1:x:=2;END_IF;END_FUNCTION_BLOCK')
        self.assertTrue(any('END_CASE' in e['message'] for e in errors))
    def test_repair_selection_uses_latest_equal_progress_but_keeps_stronger_candidate(self):
        def attempt(i,count,passed=0,native=False):return dict(idx=i,code='code'+str(i),provider_error='',functional_pass=False,native_pass=native,native_eligible=True,compiles=native,tests_passed=passed,verification_status='not_run',judge=dict(compile_errors=[dict(message='error')]*count))
        self.assertEqual(select([attempt(0,1),attempt(1,1)]),1)
        self.assertEqual(select([attempt(0,3),attempt(1,1)]),1)
        self.assertEqual(select([attempt(0,0,10,True),attempt(1,0,9,True)]),0)
    def test_structure_diagnostics_reach_static_gate_with_candidate_context(self):
        pid='public-medium-03';path,=s.RELEASE.glob('datasets/*/tests/'+pid+'.reference.st')
        source=path.read_text(encoding='utf-8');pos=source.rindex('END_VAR')+len('END_VAR');source=source[:pos]+'\nBEGIN\n'+source[pos:]
        result=s.run_stage(source,pid,'static',30)
        self.assertFalse(result['result']['compiles']);self.assertIn('Pascal',result['feedback']);self.assertIn('BEGIN',result['feedback'])
    def test_known_invalid_structure_skips_native_compile_but_preserves_repair_feedback(self):
        import time
        pid='public-medium-03';path,=s.RELEASE.glob('datasets/*/tests/'+pid+'.reference.st')
        source=path.read_text(encoding='utf-8');pos=source.rindex('END_VAR')+len('END_VAR');source=source[:pos]+'\nBEGIN\n'+source[pos:]
        with patch.object(s.old.old.support.CodesysBackend,'compile',side_effect=AssertionError('must not invoke native compile')):
            result=s.evaluate(source,pid,s.config(),time.monotonic()+60)
        self.assertFalse(result['result']['compiles']);self.assertIn('Pascal',result['feedback'])
    def test_feedback_contains_prior_actual_outputs_not_private_expected_values(self):
        pid='public-hard-06';path,=s.RELEASE.glob('datasets/*/tests/'+pid+'.reference.st')
        source=path.read_text(encoding='utf-8').replace('END_FUNCTION_BLOCK','firingTemp:=0.0;END_FUNCTION_BLOCK')
        result=s.run_stage(source,pid,'functional',30);text=result['feedback']
        self.assertIn('observed_outputs_after_case',text);self.assertNotIn('"expected":',text);self.assertNotIn('"note":',text)

if __name__=='__main__':unittest.main()

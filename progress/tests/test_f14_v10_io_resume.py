"""Offline controls for transient file conflicts and continuing unused repair indices."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import f14_v10_core as s
import f14_v10_budget as b
import f14_v10_io as io
from full_r8b_transport import MeteredProvider

class LocalIO(unittest.TestCase):
    def test_transient_replace_retries_only_disk_operation(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'data.json';p.write_text('{}');real=io.os.replace;seen=[]
            def replace(*args):
                seen.append(args)
                if len(seen)<3:raise PermissionError('sharing violation')
                return real(*args)
            with patch.object(io.os,'replace',side_effect=replace):io.atomic_json(p,dict(value=7))
            self.assertEqual(json.loads(p.read_text()),dict(value=7));self.assertEqual(len(seen),3)
    def test_concurrent_atomic_writes_have_unique_temporary_names(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'data.json'
            with ThreadPoolExecutor(max_workers=8) as pool:list(pool.map(lambda i:io.atomic_json(p,dict(value=i)),range(40)))
            self.assertIn(json.loads(p.read_text())['value'],range(40));self.assertFalse(list(Path(d).glob('*.tmp')))
    def test_persistent_permission_failure_is_not_hidden(self):
        with self.assertRaises(PermissionError):io.file_operation(lambda:(_ for _ in ()).throw(PermissionError('ACL')),seconds=0)
    def test_non_permission_errors_are_not_retried(self):
        with self.assertRaises(ValueError):io.file_operation(lambda:(_ for _ in ()).throw(ValueError('invalid')))

class Resume(unittest.TestCase):
    def test_resume_sends_only_fourth_unused_candidate_and_keeps_wall_budget(self):
        with tempfile.TemporaryDirectory() as d,patch.object(b,'HISTORY',0),patch.object(b,'BASELINE',0):
            root=Path(d);ledger=root/'ledger.json';condition='custom_deepseek-v4pro';pid='public-easy-01'
            job=dict(pid=pid,framework='custom',model_id='deepseek-v4pro',condition=condition,job_id=condition+'/'+pid,first_upper_cny=2,repair_upper_cny=2)
            job['initial_user_sha256']=hashlib.sha256(s.messages(job)[1]['content'].encode()).hexdigest()
            before=dict(version=3,limit_cny=210,spent_cny=0,events=[],recoveries=[])
            state=dict(before,limit_cny=420,halted='',f14_v10_authorization=dict(study_plan_sha256='plan',total_cap_cny=420))
            s.atomic_json(ledger,state);s.atomic_json(root/'study_plan.json',{})
            co=b.Coordinator(ledger,dict(sha256='plan',jobs=[job]),baseline=before);view=co.view(job['job_id']);attempts=[]
            for idx in range(3):
                code=f'FUNCTION_BLOCK FB VAR_OUTPUT x:INT;END_VAR x:={idx};END_FUNCTION_BLOCK'
                view.context=dict(job_id=job['job_id'],candidate_index=idx);event=view.reserve(0);view.settle(event,0)
                attempts.append(dict(idx=idx,code=code,code_hash=hashlib.sha256(code.encode()).hexdigest(),functional_pass=False,native_pass=True,native_eligible=True,compiles=True,tests_passed=0,tests_total=1,verification_status='not_run',judge={},feedback='Observed execution mismatch',provider_error=''))
            path=root/'jobs'/condition/(pid+'.json')
            s.atomic_json(path,dict(job_id=job['job_id'],pid=pid,condition=condition,job_done=False,stop_reason='campaign_stopped_before_send',attempts=attempts,best_attempt=0,wall_seconds=150,tests_total=1))
            sends=[]
            def factory(spec,budget,**kwargs):
                def sender(*args):
                    sends.append(budget.context['candidate_index'])
                    return dict(model=spec['model'],status='completed',usage=dict(input_tokens=0,output_tokens=0),output=[dict(type='message',content=[dict(type='output_text',text='FUNCTION_BLOCK FB VAR_OUTPUT x:INT;END_VAR x:=99;END_FUNCTION_BLOCK')])])
                return MeteredProvider(spec,budget,**kwargs,offline=True,sender=sender)
            def evaluate(*args):return dict(result=dict(compiles=True,compile_errors=[],tests_total=1,tests_passed=1,platform_results=dict(codesys=dict(status='passed'))),verification_status='truncated',feedback='ok',complete_code=True,shared_tool_error=False)
            result=s.generate_job(s.config(),root,{},job,view,{},factory=factory,evaluator=evaluate,resume=True)
            self.assertEqual(sends,[3]);self.assertEqual(len(result['attempts']),4);self.assertTrue(result['job_done']);self.assertGreaterEqual(result['wall_seconds'],150)
            self.assertTrue((path.parent/(pid+'.request_04.json')).exists());self.assertFalse((path.parent/(pid+'.request_01.json')).exists())

if __name__=='__main__':unittest.main()

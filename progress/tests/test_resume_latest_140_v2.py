"""Resume exact-edit repairs through both models and real CLI, using only mock upstreams."""
from concurrent.futures import ThreadPoolExecutor
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import f14_v14_core as s
import f14_v14_budget as b
from resume_latest_140_v2 import resumed_generator,LIMITS,next_job_index
from full_r8b_transport import MeteredProvider

BAD='FUNCTION_BLOCK FB VAR_OUTPUT x:BOOL;END_VAR x:=FALSE;END_FUNCTION_BLOCK'
GOOD=BAD.replace('FALSE','TRUE')

class ResumeTests(unittest.TestCase):
    def test_deepseek_finishes_before_minimax_and_lane_caps_hold(self):
        ds=dict(model_id='deepseek-v4pro');mm=dict(model_id='minimax-m27')
        self.assertEqual(next_job_index([mm,ds],{}),1)
        self.assertIsNone(next_job_index([mm],{0:ds}))
        self.assertIsNone(next_job_index([ds,mm],{i:ds for i in range(8)}))
        self.assertEqual(next_job_index([mm],{}),0)
        self.assertIsNone(next_job_index([mm],{0:mm,1:mm}))

    def test_only_resume_context_changes_and_model_lanes_are_bounded(self):
        _,proof=resumed_generator()
        self.assertTrue(proof['fresh_prefix_unchanged']);self.assertTrue(proof['execution_suffix_unchanged'])
        self.assertEqual(LIMITS,{'deepseek-v4pro':8,'minimax-m27':2})

    def test_all_four_arms_resume_next_candidate_with_exact_patch_and_no_repeat(self):
        with tempfile.TemporaryDirectory() as directory,patch.object(b,'HISTORY',3),patch.object(b,'BASELINE',10):
            root=Path(directory);path=root/'ledger.json';cfg=s.config();jobs=[]
            for framework,mid in s.old.ARMS:
                pid='public-easy-01';condition=framework+'_'+mid
                jobs.append(dict(pid=pid,framework=framework,model_id=mid,condition=condition,job_id=condition+'/'+pid,first_upper_cny=2,repair_upper_cny=2))
            before=dict(version=3,limit_cny=480,spent_cny=10,events=[dict(phase='history') for _ in range(3)],recoveries=[],historical_authorization=dict(keep=True))
            state=copy.deepcopy(before);state.update(halted='',f14_v14_authorization=dict(total_cap_cny=480,study_plan_sha256='plan'),active_experiment_scope=dict(conditions=[j['condition'] for j in jobs]))
            s.atomic_json(path,state);s.atomic_json(root/'study_plan.json',{})
            co=b.Coordinator(path,dict(sha256='plan',jobs=jobs),baseline=before);original={}
            def evaluation(code,*args):
                success=code==GOOD
                return dict(result=dict(compiles=True,compile_errors=[],tests_total=1,tests_passed=int(success),platform_results=dict(codesys=dict(status='passed'))),
                    verification_status='bounded_pass' if success else 'not_run',feedback='A public output failed; actual output is FALSE.',complete_code=True,shared_tool_error=False)
            for job in jobs:
                view=co.view(job['job_id']);view.context=dict(job_id=job['job_id'],candidate_index=0);index=view.reserve(0);view.settle(index,0,metadata=dict(model='mock'))
                a=s.classify(evaluation(BAD));a.update(idx=0,code=BAD,code_hash=hashlib.sha256(BAD.encode()).hexdigest(),provider_error='',cost_cny=0)
                record=dict(job_id=job['job_id'],pid=job['pid'],condition=job['condition'],job_done=False,attempts=[a],best_attempt=0,
                    stop_reason='campaign_stopped_before_send',tests_total=10,wall_seconds=100,started_at=s.stamp())
                original[job['job_id']]=copy.deepcopy(a)
                folder=root/'jobs'/job['condition'];s.atomic_json(folder/(job['pid']+'.json'),record)
                (folder/(job['pid']+'.request_01.json')).write_text('{"mock_prior_request":true}')
            def factory(spec,budget,**kwargs):
                def sender(*args):
                    self.assertEqual(budget.context['candidate_index'],1)
                    text=json.dumps(dict(edits=[dict(old='x:=FALSE;',new='x:=TRUE;')]))
                    if spec['generation_protocol']=='chat':return dict(model=spec['model'],usage=dict(prompt_tokens=0,completion_tokens=0),choices=[dict(finish_reason='stop',message=dict(content=text))])
                    return dict(model=spec['model'],status='completed',usage=dict(input_tokens=0,output_tokens=0),output=[dict(type='message',content=[dict(type='output_text',text=text)])])
                return MeteredProvider(spec,budget,**kwargs,offline=True,sender=sender)
            generate,_=resumed_generator()
            with ThreadPoolExecutor(max_workers=4) as pool:
                results=list(pool.map(lambda j:generate(cfg,root,{},j,co.view(j['job_id']),{},factory=factory,evaluator=evaluation,resume=True),jobs))
            for job,record in zip(jobs,results):
                self.assertTrue(record['job_done']);self.assertEqual(record['attempts'][0],original[job['job_id']])
                self.assertEqual(record['attempts'][1]['code'],GOOD);self.assertEqual(record['attempts'][1]['model_patch']['mode'],'model_exact_edits')
                request=s.load(root/'jobs'/job['condition']/(job['pid']+'.request_02.json'))
                self.assertIn('REPAIR OUTPUT MODE',json.dumps(request));self.assertFalse((root/'jobs'/job['condition']/(job['pid']+'.request_03.json')).exists())
            events=co.read()['events'][3:]
            self.assertEqual(len(events),8)
            self.assertEqual(len({(e['request']['job_id'],e['request']['candidate_index']) for e in events}),8)

if __name__=='__main__':unittest.main()

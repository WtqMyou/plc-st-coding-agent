"""No paid calls: ledger, repair, privacy, pause and real local CLI contract checks."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import full_r8_study as s
from full_r8_budget import StudyBudget,ReviewPause,migrate
from stbench.billing import CampaignBudget
from stbench.providers.base import ProviderError
from stbench.st.driver import StageResult,CaseResult
from stbench.transport import MeteredProvider

A='FUNCTION_BLOCK FB VAR x:INT; END_VAR x:=0; END_FUNCTION_BLOCK'
B='FUNCTION_BLOCK FB VAR x:INT; END_VAR x:=1; END_FUNCTION_BLOCK'

class FullStudy(unittest.TestCase):
    def setup_case(self,directory,fw='custom',mid='minimax-m27',spent=None):
        cfg=copy.deepcopy(s.config());root=Path(directory)/'study';root.mkdir()
        cfg['campaign_root']=str(root);cfg['platform_root']=directory
        cfg['budget_ledger_path']=str(Path(directory)/'ledger.json')
        state=dict(version=3,limit_cny=75,spent_cny=s.BASELINE,events=[dict(request_id=str(n),status='settled',accounted_cny=0) for n in range(450)],halted='',recoveries=[dict(old='preserved')])
        s.atomic_json(Path(cfg['budget_ledger_path']),state)
        plan=s.make_plan(cfg,state,[]);s.atomic_json(root/'study_plan.json',plan)
        raw=Path(cfg['budget_ledger_path']).read_bytes()
        migrate(cfg['budget_ledger_path'],raw,s.sha(root/'study_plan.json'),'test')
        budget=StudyBudget(cfg['budget_ledger_path'],s.sha(root/'study_plan.json'))
        if spent is not None:
            changed=budget.read();changed['spent_cny']=spent;s.atomic_json(budget.path,changed)
        job=next(j for j in plan['jobs'] if j['framework']==fw and j['model_id']==mid)
        pending={j['job_id']:float(s.money(j['first_upper_cny'])+s.money(j['repair_upper_cny'])) for j in plan['jobs']}
        return cfg,root,plan,budget,job,pending,state,raw
    def result(self,problem,kind='pass'):
        r=StageResult(True,tests_total=len(problem.test_cases),tests_passed=len(problem.test_cases),
                      platform_results={'codesys':dict(status='passed')},evidence_metadata=dict(classification='evaluated'))
        if kind=='compile':
            r.compiles=False;r.tests_passed=0;r.compile_errors=[dict(line=1,code='E_FIXTURE',message='fixture compile diagnostic')];r.evidence_metadata['classification']='candidate_static_error';r.platform_results={}
        if kind=='functional':
            r.tests_passed-=1;r.cases=[CaseResult('fixture',False,expected={'out':'SECRET_EXPECTED_LITERAL'},actual={'out':0})]
        if kind=='formal':
            r.mc_executed=True;r.mc_specs_total=1;r.mc_specs_violated=1
            r.mc_violations=[dict(id='S_fixture',formula='G safe',at=1)]
        if kind=='truncated':r.mc_executed=True;r.mc_specs_total=1;r.mc_truncated=True
        return r
    def run_fake(self,directory,kind='functional',fw='custom',mid='minimax-m27',finish='stop',same=False,wrong=False):
        cfg,root,plan,budget,job,pending,_,_=self.setup_case(directory,fw,mid)
        calls=[];evaluations=[]
        def sender(url,payload,key,timeout):
            calls.append(payload)
            code=A if len(calls)==1 or same else B
            text='' if finish=='length' else code
            model='unexpected-model' if wrong else next(m for m in cfg['models'] if m['id']==mid)['model']
            if mid=='deepseek-v4pro':
                return dict(model=model,status='incomplete' if finish=='length' else 'completed',usage=dict(input_tokens=1,output_tokens=2),
                            output=[dict(type='message',content=[dict(type='output_text',text=text)])])
            return dict(model=model,usage=dict(prompt_tokens=1,completion_tokens=2),
                        choices=[dict(finish_reason=finish,message=dict(content=text,reasoning_content='fixture'))])
        def factory(m,b,**kwargs):return MeteredProvider(m,b,**kwargs,sender=sender,offline=True)
        def evaluate(src,p):
            evaluations.append(src)
            return self.result(p,kind if len(evaluations)==1 else 'truncated')
        record=s.generate_job(cfg,root,plan,job,budget,pending,factory=factory,evaluator=evaluate)
        return record,calls,evaluations,budget,root,job
    def test_coverage_and_rotation(self):
        jobs=s.jobs();self.assertEqual(len(jobs),140);self.assertEqual(len({j['job_id'] for j in jobs}),140)
        for fw,mid in s.ARMS:
            self.assertEqual(sum(j['framework']==fw and j['model_id']==mid for j in jobs),35)
        self.assertEqual([j['condition'] for j in jobs[:4]],list(reversed([j['condition'] for j in jobs[4:8]])))
    def test_data_and_mc_policy(self):
        self.assertEqual(sum(len(p.test_cases) for p in s.data().values()),1214)
        self.assertTrue(all(p.mc_max_seconds==30 for p in s.data().values()))
        self.assertEqual(s.old.selected()['public-easy-04'].mc_max_seconds,30)
    def test_plan_upper_and_original_model_map(self):
        with tempfile.TemporaryDirectory() as d:
            cfg,r,p,b,j,pending,old,raw=self.setup_case(d)
            self.assertAlmostEqual(p['worst_reservation_cny'],125.604056,places=6)
            self.assertLess(s.BASELINE+p['worst_reservation_cny'],170)
            self.assertEqual(cfg['models'],s.load(s.old.CONFIG)['models'])
    def test_measured_input_can_stop_preparation(self):
        with tempfile.TemporaryDirectory() as d:
            cfg,r,p,b,j,pending,old,raw=self.setup_case(d)
            rows=[dict(job_id=x['job_id'],upstream_message_bytes=1000000) for x in p['jobs']]
            with self.assertRaises(AssertionError):s.make_plan(cfg,old,rows)
    def test_migration_preserves_history_and_accounting(self):
        with tempfile.TemporaryDirectory() as d:
            cfg,r,p,b,j,pending,old,raw=self.setup_case(d)
            now=b.read();self.assertTrue(s.prefix_ok(now,old));self.assertEqual(now['spent_cny'],old['spent_cny']);self.assertEqual(now['limit_cny'],170)
            before=b.path.read_bytes();migrate(b.path,raw,s.sha(r/'study_plan.json'),'another-time');self.assertEqual(before,b.path.read_bytes())
    def test_migration_rejects_changed_baseline(self):
        with tempfile.TemporaryDirectory() as d:
            cfg,r,p,b,j,pending,old,raw=self.setup_case(d)
            now=b.read();now.pop('full_r8_authorization');now['limit_cny']=75;now['spent_cny']+=.1;s.atomic_json(b.path,now)
            with self.assertRaises(ProviderError):migrate(b.path,raw,s.sha(r/'study_plan.json'),'test')
    def test_legacy_budget_refuses_migrated_limit(self):
        with tempfile.TemporaryDirectory() as d:
            cfg,r,p,b,*_=self.setup_case(d)
            with self.assertRaises(ProviderError):CampaignBudget(b.path,'final').read()
    def test_admit_job_at_review_boundary(self):
        with tempfile.TemporaryDirectory() as d:
            cfg,r,p,b,*_=self.setup_case(d,spent=79.5)
            b.admit_job(.5)
            before=b.path.read_bytes()
            with self.assertRaises(ReviewPause):b.admit_job(.500001)
            self.assertEqual(before,b.path.read_bytes())
    def test_request_crossing_review_has_zero_new_events(self):
        with tempfile.TemporaryDirectory() as d:
            cfg,r,p,b,*_=self.setup_case(d,spent=79.99)
            before=b.path.read_bytes()
            with self.assertRaises(ReviewPause):b.reserve(.010001)
            self.assertEqual(before,b.path.read_bytes())
    def test_global_coverage_is_independent_of_review(self):
        with tempfile.TemporaryDirectory() as d:
            cfg,r,p,b,*_=self.setup_case(d)
            b.protected_cny=125
            b.reserve(.1)
            self.assertEqual(len(b.read()['events']),451)
    def test_global_limit_cannot_be_relaxed(self):
        with tempfile.TemporaryDirectory() as d:
            cfg,r,p,b,*_=self.setup_case(d)
            b.protected_cny=131
            before=b.path.read_bytes()
            with self.assertRaises(ProviderError):b.reserve(1)
            self.assertEqual(before,b.path.read_bytes())
    def test_explicit_checkpoint_change_is_bounded(self):
        with tempfile.TemporaryDirectory() as d:
            cfg,r,p,b,*_=self.setup_case(d)
            for invalid in (79,170.1):
                with self.assertRaises(ProviderError):StudyBudget(b.path,s.sha(r/'study_plan.json'),invalid)
            resumed=StudyBudget(b.path,s.sha(r/'study_plan.json'),170)
            state=resumed.read();state['spent_cny']=169.9;s.atomic_json(b.path,state)
            with self.assertRaises(ReviewPause):resumed.reserve(.100001)
    def test_all_feedback_types_both_models_and_real_cli(self):
        for kind in ('compile','functional','formal'):
            for fw,mid in s.ARMS:
                with self.subTest(kind=kind,framework=fw,model=mid),tempfile.TemporaryDirectory() as d:
                    record,calls,ev,b,r,job=self.run_fake(d,kind,fw,mid)
                    self.assertEqual(len(calls),2);self.assertEqual(len(ev),2);self.assertEqual(record['n_attempts'],2);self.assertTrue(record['solved'])
                    second=s.load(r/'jobs'/job['condition']/(job['pid']+'.request_02.json'))
                    text=json.dumps(second,ensure_ascii=False)
                    self.assertTrue(any(record['attempts'][0]['feedback'][:4000].replace('\r\n','\n') in m['content'].replace('\r\n','\n') for m in second['messages']))
                    self.assertNotIn('SECRET_EXPECTED_LITERAL',text)
                    self.assertEqual(len(b.read()['events']),452)
    def test_pass_and_truncation_do_not_spend_repair(self):
        for kind in ('pass','truncated'):
            with self.subTest(kind=kind),tempfile.TemporaryDirectory() as d:
                record,calls,ev,*_=self.run_fake(d,kind)
                self.assertEqual(len(calls),1);self.assertTrue(record['solved'])
    def test_known_empty_length_is_not_regenerated(self):
        with tempfile.TemporaryDirectory() as d:
            record,calls,ev,b,r,job=self.run_fake(d,finish='length')
            self.assertEqual(len(calls),1);self.assertEqual(ev,[]);self.assertTrue(record['job_done'])
            self.assertEqual(record['stop_reason'],'generation_incomplete')
            response=s.load(r/'jobs'/job['condition']/(job['pid']+'.response_01.json'))
            self.assertEqual(response['raw_response']['choices'][0]['message']['content'],'')
            self.assertEqual(b.read()['events'][-1]['status'],'settled')
    def test_repeated_candidate_stops_after_two_calls_one_evaluation(self):
        with tempfile.TemporaryDirectory() as d:
            record,calls,ev,*_=self.run_fake(d,same=True)
            self.assertEqual(len(calls),2);self.assertEqual(len(ev),1);self.assertEqual(record['stop_reason'],'repeated_candidate')
    def test_unknown_identity_retains_reserve_and_stops(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(ProviderError):self.run_fake(d,wrong=True)
            ledger=s.load(Path(d)/'ledger.json')
            self.assertTrue(ledger['halted']);self.assertEqual(ledger['events'][-1]['status'],'reserved')
    def test_duplicate_trace_refuses_second_run(self):
        with tempfile.TemporaryDirectory() as d:
            cfg,r,p,b,j,pending,*_=self.setup_case(d)
            folder=r/'jobs'/j['condition'];folder.mkdir(parents=True)
            (folder/(j['pid']+'.request_01.json')).write_text('existing')
            with self.assertRaises(RuntimeError):s.generate_job(cfg,r,p,j,b,pending)
            self.assertEqual(len(b.read()['events']),450)
    def test_resume_skips_done_and_refuses_partial(self):
        with tempfile.TemporaryDirectory() as d:
            cfg,r,p,b,j,pending,*_=self.setup_case(d)
            folder=r/'jobs'/j['condition'];folder.mkdir(parents=True)
            s.atomic_json(folder/(j['pid']+'.json'),dict(job_done=True))
            self.assertNotIn(j['job_id'],s.remaining_jobs(r,p))
            s.atomic_json(folder/(j['pid']+'.json'),dict(job_done=False))
            with self.assertRaises(AssertionError):s.remaining_jobs(r,p)
    def test_unsupported_and_public_tool_failure_not_repaired(self):
        p=next(iter(s.data().values()))
        r=self.result(p,'functional');r.evidence_metadata['classification']='unsupported_modeling';self.assertFalse(s.repairable(r))
        r.evidence_metadata['classification']='tool_error';r.mc_error='r5 worker timeout'
        self.assertTrue(s.public_failure(r))
    def test_dashboard_reads_without_model_calls(self):
        from full_r8_report import metrics,html
        with tempfile.TemporaryDirectory() as d:
            cfg,r,p,b,j,pending,old,raw=self.setup_case(d)
            (r/'ledger_before_study.json').write_bytes(raw);s.atomic_json(r/'study_state.json',dict(state='prepared'))
            before=b.path.read_bytes();summary=metrics(cfg,p);page=html(cfg,p,summary)
            self.assertIn('0/140',page);self.assertIn('170',page);self.assertEqual(summary['rows'][0]['tests_total'],1214)
            self.assertEqual(before,b.path.read_bytes())

if __name__=='__main__':unittest.main()

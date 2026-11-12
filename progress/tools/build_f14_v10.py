"""One-time V10 seed scaffold; final reviewed sources are committed separately.
This preserves the initial copy operation, not a rebuild command for the final package.
"""
import json
from pathlib import Path
import shutil

REPO=Path(__file__).resolve().parents[2]
ROOT=REPO/'progress/f14_agent_v10'

def replace(text, old, new):
    assert old in text,old[:100]
    return text.replace(old,new)

def main():
    assert not ROOT.exists(),'Never overwrite a study package'
    ROOT.mkdir()
    prior=REPO/'progress/f14_v7_boundary_review'
    shutil.copytree(prior/'release',ROOT/'release',ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
    shutil.copytree(prior/'reference_controls',ROOT/'reference_controls')
    for name in ('judge_worker.py','judge_audit_worker.py','runtime_probe.py','contract_check.py'):
        text=(prior/name).read_text(encoding='utf-8').replace('v6_contracts','v10_contracts')
        (ROOT/name).write_text(text,encoding='utf-8')
    for name in ('contracts','extraction','formatting'):
        text=(REPO/f'progress/f14_agent_v6/v6_{name}.py').read_text(encoding='utf-8').replace('v6_contracts','v10_contracts')
        (ROOT/f'v10_{name}.py').write_text(text,encoding='utf-8')
    for name in ('public_time_bounds.py','policy.py'):
        shutil.copyfile(REPO/'progress/f14_v9_temperature_minimal'/name,ROOT/name)
    cfg=json.loads((REPO/'progress/f14_agent_v6/config.json').read_text(encoding='utf-8'))
    cfg.update(budget_cny=420,user_authorized_total_cap_cny=420,campaign_root='E:/PLC_Dev/evidence/real_experiments/f14_v10_full_20261113')
    cfg['study'].update(kind='f14_v10_full_20261113',total_cap_cny=420,max_requests=560,initial_spent_cny=123.593292,initial_event_count=1266)
    cfg['concurrency'].update(max_jobs=8,per_model_requests=4,ramp_after_jobs=4)
    (ROOT/'config.json').write_text(json.dumps(cfg,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    tools=REPO/'progress/tools'
    for name in ('core','budget','study','report','offline','preflight'):
        text=(tools/f'f14_v6_{name}.py').read_text(encoding='utf-8')
        for a,b in [('f14_v6','f14_v10'),('v6_extraction','v10_extraction'),('v6_formatting','v10_formatting'),('v6_contracts','v10_contracts'),
                    ('f14_agent_v6','f14_agent_v10'),('public_pilot_20261112','full_20261113'),('preflight_20261112','preflight_20261113'),
                    ('112.728371','123.593292'),('1183','1266'),('210','420'),('96','560')]:text=text.replace(a,b)
        if name=='core':
            text=replace(text,'threading.Semaphore(2) for key','threading.Semaphore(4) for key')
            text=replace(text,"rows=all_tasks();return {pid:rows[pid] for pid in PIDS}",'return all_tasks()')
            text=replace(text,'==24 and routes','==140 and routes')
            text=text.replace('planned=24','planned=140').replace('native_eligible_tasks=6','native_eligible_tasks=34')
            text=replace(text,'import f14_v5_core as prior','import f14_v6_core as prior')
            text=replace(text,"('core','budget','study','report','offline','preflight')","('core','budget','study','report','offline','preflight')")
            text=replace(text,"money(job['first_upper_cny'])+money(job['repair_upper_cny'])","money(job['first_upper_cny'])+3*money(job['repair_upper_cny'])")
            text=replace(text,"    return [dict(role='system',content=contract),dict(role='user',content=user)]","    from public_time_bounds import derive\n    contract+='\\nPublic-text discrete-time boundary arithmetic (not test data):\\n'+json.dumps(derive(user),ensure_ascii=False)\n    return [dict(role='system',content=contract),dict(role='user',content=user)]")
            text=replace(text,"instruction=strongest['feedback']+", "from policy import BOUNDARY_REVIEW\n                    instruction=BOUNDARY_REVIEW+'\\n'+strongest['feedback']+")
        elif name=='budget':
            text=replace(text,"==(TOTAL,BASELINE,HISTORY)","==(210,BASELINE,HISTORY)")
            text=replace(text,"after=json.loads(before_bytes)","after=json.loads(before_bytes)\n        after['limit_cny']=TOTAL")
            text=replace(text,"按照你说的做好修改，然后启动付费实验；沿用420元累计上限，六道公共题四组、每题最多4候选；用户要求进行下一步","提高到420元，保留每题最多4候选并直接启动")
        elif name=='study':
            text=replace(text,"ledger['limit_cny']==TOTAL","ledger['limit_cny']==210")
            text=replace(text,"original_user_answers=['提高到420元，修复验收后直接启动','进行下一步']","original_user_answers=['提高到420元，保留每题最多4候选并直接启动','完成这四步，直到开始全量独立验证后停止工作让它自己测验，我明早来查看结果']")
            text=replace(text,"scope='six public tasks, four arms, up to four candidates each, maximum 560 requests'","scope='35 tasks (20 public and 15 custom), four arms, up to four candidates per job, maximum 560 requests'")
            text=text.replace('local_routes=24','local_routes=140').replace('PREPARED 24','PREPARED 140').replace("'/24'","'/140'").replace('done_count==24','done_count==140').replace('jobs=24','jobs=140')
            text=replace(text,'max_workers=4,thread_name_prefix','max_workers=8,thread_name_prefix')
            text=replace(text,'if done_count>=4 and not budget.stopped.is_set():limit=4','if cursor>=4 and done_count>=4 and not budget.stopped.is_set():limit=8')
            text=text.replace('default=8890','default=8893')
        elif name=='offline':
            text=replace(text,"first=s.money(((size+6144)*model['input_cny_per_million']+16384*model['output_cny_per_million'])/1e6)","assert size+4096<=65536,'Actual CLI route exceeds frozen request bound'\n            first=s.money((65536*model['input_cny_per_million']+16384*model['output_cny_per_million'])/1e6)")
            text=text.replace("'/24'","'/140'").replace('real_cli_invocations=12','real_cli_invocations=70').replace('PASS 24','PASS 140')
        elif name=='report':
            text=text.replace('planned=24','planned=140').replace('jobs=24','jobs=140').replace('/24','/140').replace('24题次完成','140题次完成')
        (tools/f'f14_v10_{name}.py').write_text(text,encoding='utf-8')
    text=(REPO/'progress/tests/test_f14_v6.py').read_text(encoding='utf-8').replace('f14_v6','f14_v10').replace('v6_contracts','v10_contracts')
    text=replace(text,"state.update(limit_cny=210,halted='',f14_v10_authorization=dict(study_plan_sha256='plan',total_cap_cny=210))","state.update(limit_cny=420,halted='',f14_v10_authorization=dict(study_plan_sha256='plan',total_cap_cny=420))")
    text=replace(text,"self.co.pending['huge']={0:s.money(199)}","self.co.pending['huge']={0:s.money(419)}")
    text=replace(text,'test_maximum_96_requests_blocks_the_97th_before_charging','test_maximum_560_requests_blocks_the_561st_before_charging')
    text=replace(text,'range(40)','range(141)').replace('first_upper_cny=.6,repair_upper_cny=.9','first_upper_cny=.1,repair_upper_cny=.1')
    # Most fixture assertions need larger individual bounds; do not inflate 141 pending jobs.
    text=replace(text,"self.jobs=[dict(job_id=","self.jobs=[dict(job_id=")
    text=replace(text,"self.co=b.Coordinator(self.path,self.plan,baseline=self.before)","self.co=b.Coordinator(self.path,self.plan,baseline=self.before)\n        for bounds in self.co.bounds.values():\n            for idx in bounds:bounds[idx]=s.money(.9)\n        self.co.pending={k:dict(v) for k,v in self.co.bounds.items()}\n        for key in list(self.co.pending)[40:]:self.co.pending[key]={i:s.money(0) for i in range(4)}")
    text=text.replace('range(24)','range(140)').replace('self.view(24).reserve(0)','self.view(140).reserve(0)')
    text=replace(text,"self.assertEqual(state['limit_cny'],210)","self.assertEqual(state['limit_cny'],420)")
    text=replace(text,'self.assertLessEqual(peak,4)','self.assertLessEqual(peak,4)')
    # A restored coordinator uses .1 bounds, so a duplicate is still rejected before size matters.
    (REPO/'progress/tests/test_f14_v10.py').write_text(text,encoding='utf-8')
    print('Created separate V10 full-study package; no ledger mutation or API request')

if __name__=='__main__':main()

"""Signed condition selection; prior answers, costs and other groups remain intact."""
from pathlib import Path
import copy
import hashlib
import f14_v11_core as s
from stbench.billing import ledger_lock

CONDITION='custom_deepseek-v4pro'

def selected_jobs(plan,condition):
    if condition is None:return plan['jobs']
    assert condition==CONDITION,'Only the explicitly requested self-built DeepSeek scope is enabled'
    jobs=[j for j in plan['jobs'] if j['condition']==condition]
    assert len(jobs)==20 and all(j['framework']=='custom' and j['model_id']=='deepseek-v4pro' for j in jobs)
    return jobs

def activate(cfg,condition):
    assert condition==CONDITION
    root=Path(cfg['campaign_root']);stage=s.load(root/'self_stage_control.json');path=Path(cfg['budget_ledger_path'])
    assert stage['condition']==condition and stage['plan_sha256']==s.sha(root/'study_plan.json')
    with ledger_lock(path):
        before=path.read_bytes();state=s.load(path)
        assert hashlib.sha256(before).hexdigest()==stage['ledger_before_sha256']
        assert state['halted']=='USER_PAUSE_V11_DEEPSEEK_FIRST'
        previous=copy.deepcopy(state)
        state['halted']='';state['active_experiment_scope']=dict(condition=condition,target=18,tasks=20,stage_sha256=s.sha(root/'self_stage_control.json'))
        state['f14_v11_authorization'].setdefault('operational_plan_sha256',[]).append(stage['plan_sha256'])
        state['recoveries'].append(dict(kind=s.KIND,reason='user_resumes_only_custom_deepseek',user_instruction='启动deepseek自研组的测试',
            at=s.stamp(),condition=condition,remaining_groups_paused=True,no_requests_resent=True,prior_timeout_reservation_retained=True))
        assert state['events']==previous['events'] and state['spent_cny']==previous['spent_cny']
        s.atomic_json(path,state)
    s.atomic_json(root/'ledger_checkpoint.json',dict(sha256=s.sha(path),at=s.stamp()))

def check_other_records(root):
    root=Path(root);stage=s.load(root/'self_stage_control.json')
    for rel,digest in stage['other_record_hashes'].items():assert s.sha(root/rel)==digest,'Another group record changed'

def audit(cfg,plan,condition):
    root=Path(cfg['campaign_root']);state=s.load(cfg['budget_ledger_path']);jobs=selected_jobs(plan,condition)
    events=[e for e in state['events'][s.HISTORY:] if e['request']['job_id'].startswith(condition+'/')]
    linked={(e['request']['job_id'],e['request']['candidate_index']):e for e in events}
    assert len(events)==len(linked)<=80
    passed=0;cases=0;calls=0
    for j in jobs:
        folder=root/'jobs'/condition;r=s.load(folder/(j['pid']+'.json'))
        assert r['job_done'] and 1<=len(r['attempts'])<=4 and r['best_attempt']==s.select_best(r['attempts'])
        best=r['attempts'][r['best_attempt']];passed+=best['functional_pass'];cases+=best['tests_passed']
        for a in r['attempts']:
            e=linked[(j['job_id'],a['idx'])];assert e['status']=='settled'
            assert s.money(e['accounted_cny'])==s.money(a['cost_cny'])
            assert a['actual_model']==e['metadata']['model']
            for key in ('prompt_tokens','completion_tokens'):assert a[key]==e['metadata'][key]
            for kind in ('request','response'):assert (folder/(j['pid']+f'.{kind}_{a["idx"]+1:02}.json')).is_file()
            if a.get('code'):
                raw=(folder/(j['pid']+f'.raw_candidate_{a["idx"]+1:02}.st')).read_bytes().decode('utf-8');normalized,edits=s.normalize(raw)
                assert normalized==a['code'] and edits==a['format_edits']
                assert (folder/(j['pid']+f'.candidate_{a["idx"]+1:02}.st')).read_bytes()==normalized.encode()
                native=a.get('judge',{}).get('platform_results',{}).get('codesys',{})
                if native.get('status')=='passed':assert native['source_sha256']==a['code_hash']
            calls+=1
    assert calls==len(events);check_other_records(root)
    return dict(passed=True,condition=condition,jobs=20,requests=calls,functional_passed=passed,assertions_passed=cases,assertions_total=470,
        target_passed=18,target_met=passed>=18,other_groups_unchanged=True,other_groups_still_paused=True,at=s.stamp())

"""Recover captured replies and amend only V10's duplicate-observer plumbing."""
import copy, hashlib, json, time
from pathlib import Path
import f14_v10_core as s
from f14_v10_budget import HISTORY, KIND, money
from stbench.billing import ledger_lock
from stbench.transport import validate_response

def main():
 cfg=s.config(); root=Path(cfg['campaign_root']); stamp=root/'recovery_capture_fix_20261113'; assert not (stamp/'recovery.json').exists(); stamp.mkdir(exist_ok=True)
 plan=s.load(root/'study_plan.json'); old_sha=s.sha(root/'study_plan.json'); (stamp/'study_plan.before.json').write_bytes((root/'study_plan.json').read_bytes())
 repaired=[]; closed=[]
 for p in sorted(root.glob('jobs/*/*.json')):
  r=s.load(p)
  if 'job_id' not in r: continue
  if r.get('job_done') and r.get('stop_reason')!='recovered_capture_error': continue
  err=r.get('error','')
  if err=='Upstream validation PermissionError' or r.get('stop_reason')=='recovered_capture_error':
   idx=next((a['idx'] for a in r['attempts'] if a.get('provider_error')==err),0); raw=s.load(p.with_name(p.stem+f'.response_{idx+1:02}.json'))['raw_response']; mid=r['condition'].split('_',1)[1]
   model=next(x for x in cfg['models'] if x['id']==mid); v=validate_response(raw,model['generation_protocol'],model['accepted_models']); assert v['complete']
   cost=money((v['prompt_tokens']*model['input_cny_per_million']+v['completion_tokens']*model['output_cny_per_million'])/1e6); source,edits=s.normalize(s.extract_code(v['text']))
   result=s.evaluate(source,r['pid'],cfg,time.monotonic()+600); a=s.classify(result); a.update(idx=idx,code=source,code_hash=hashlib.sha256(source.encode()).hexdigest(),engineering_contract=s.compliance(source),actual_model=v['model'],prompt_tokens=v['prompt_tokens'],completion_tokens=v['completion_tokens'],cost_cny=float(cost),latency_s=None,generation_seconds=None,end_to_end_seconds=None,format_edits=edits,raw_source_sha256=hashlib.sha256(s.extract_code(v['text']).encode()).hexdigest(),provider_error='')
   (p.parent/(p.stem+f'.raw_candidate_{idx+1:02}.st')).write_text(s.extract_code(v['text']),encoding='utf-8'); (p.parent/(p.stem+f'.candidate_{idx+1:02}.st')).write_text(source,encoding='utf-8')
   r['attempts'][idx]=a; repaired.append((r['job_id'],idx,float(cost),v))
  r.update(job_done=True,stop_reason='recovered_capture_error' if err else 'interrupted_after_recorded_candidates_no_replay',error='',best_attempt=s.select_best(r['attempts']),finished_at=s.stamp()); s.atomic_json(p,r); closed.append(r['job_id'])
 with ledger_lock(Path(cfg['budget_ledger_path'])):
  led=s.load(cfg['budget_ledger_path']); assert led.get('halted')=='Malformed upstream result; reservation retained'
  for job,idx,cost,v in repaired:
   e=next(x for x in led['events'][HISTORY:] if x['request']['job_id']==job and x['request']['candidate_index']==idx); assert e['status']=='reserved'; led['spent_cny']=float(money(led['spent_cny'])-money(e['reserved_cny'])+money(cost)); e.update(status='settled',accounted_cny=cost,metadata=dict(model=v['model'],prompt_tokens=v['prompt_tokens'],completion_tokens=v['completion_tokens'],finish_reason=v['finish_reason'],protocol='responses',recovery='captured_response'))
  led['halted']=''; led['recoveries'].append(dict(kind=KIND,reason='duplicate_response_observer_permissionerror',no_model_request_sent=True,repaired=[x[:3] for x in repaired],closed_jobs=closed,at=s.stamp()))
  plan['files']={x.relative_to(s.REPO).as_posix():s.sha(x) for x in s.files()}; s.atomic_json(root/'study_plan.json',plan); new_sha=s.sha(root/'study_plan.json'); led['f14_v10_authorization']['amended_study_plan_sha256']=new_sha; s.atomic_json(Path(cfg['budget_ledger_path']),led)
 s.atomic_json(root/'prepared.json',dict(plan_sha256=new_sha,validation_sha256=s.sha(root/'validation.json'))); s.atomic_json(stamp/'recovery.json',dict(cause='duplicate response observer could write the same evidence file twice',old_plan_sha256=old_sha,new_plan_sha256=new_sha,repaired=[x[:3] for x in repaired],closed_jobs=closed,no_model_request_sent=True)); s.atomic_json(root/'ledger_checkpoint.json',dict(sha256=s.sha(cfg['budget_ledger_path']),at=s.stamp()))
 print('RECOVERED',len(repaired),len(closed))
if __name__=='__main__':main()

"""New 190/80 authorization; preserve every event in the shared historic ledger."""
import hashlib
import json
from pathlib import Path
import time
import uuid
from stbench.billing import CampaignBudget,ledger_lock,money
from stbench.evaluation import atomic_json
from stbench.providers.base import ProviderError

KIND='f14_p1_20261111a'
TOTAL=190
REVIEW=80
BASELINE=61.076553
HISTORY=653

class ReviewPause(ProviderError):pass

def prefix_ok(state,before):
    return (state['events'][:len(before['events'])]==before['events']
        and state.get('recoveries',[])==before.get('recoveries',[])
        and all(state.get(k)==v for k,v in before.items() if k.endswith('_authorization')))

def authorize(path,before_bytes,plan_sha,at):
    path=Path(path);before=json.loads(before_bytes)
    approval=dict(kind=KIND,total_cap_cny=TOTAL,review_pause_cny=REVIEW,
        initial_spent_cny=BASELINE,initial_event_count=HISTORY,previous_limit_cny=170,
        original_ledger_sha256=hashlib.sha256(before_bytes).hexdigest(),study_plan_sha256=plan_sha,
        authorized_at=at,authorization='User explicitly raised cumulative cap to 190 CNY; automatic pause near 80 CNY retained')
    with ledger_lock(path):
        state=json.loads(path.read_text(encoding='utf-8'))
        if 'f14_authorization' in state:
            current=state['f14_authorization']
            assert all(current.get(k)==v for k,v in approval.items() if k!='authorized_at')
            assert state['limit_cny']==TOTAL and prefix_ok(state,before)
            return current
        if path.read_bytes()!=before_bytes:raise ProviderError('Ledger changed before new authorization')
        if (state.get('version'),state.get('limit_cny'),state.get('spent_cny'),len(state.get('events',[])),bool(state.get('halted')))!=(3,170,BASELINE,HISTORY,False):
            raise ProviderError('Not the reviewed 653-event baseline; no automatic recovery/reset')
        state['limit_cny']=TOTAL;state['f14_authorization']=approval
        assert prefix_ok(state,before) and state['spent_cny']==before['spent_cny']
        atomic_json(path,state)
    return approval

class StudyBudget(CampaignBudget):
    def __init__(self,path,plan_sha):
        self.path=Path(path).resolve();self.phase=KIND;self.limit=TOTAL
        self.plan_sha=plan_sha;self.protected_cny=0.;self.context={}
        state=self.read();approval=state.get('f14_authorization',{})
        if (approval.get('study_plan_sha256'),approval.get('total_cap_cny'),approval.get('review_pause_cny'))!=(plan_sha,TOTAL,REVIEW):
            raise ProviderError('Missing matching explicit 190/80 authorization')
    def ceiling(self):return TOTAL
    def admit_job(self,upper):
        state=self.snapshot()
        if money(state['spent_cny'])+money(upper)>money(REVIEW):
            raise ReviewPause('Next complete job would exceed cumulative 80 CNY review checkpoint')
    def reserve(self,amount,*,request=None):
        amount=money(amount)
        with ledger_lock(self.path):
            state=self.read()
            if money(state['spent_cny'])+amount>money(REVIEW):
                raise ReviewPause('Next request would exceed cumulative 80 CNY review checkpoint')
            if money(state['spent_cny'])+amount+money(self.protected_cny)>money(TOTAL):
                raise ProviderError('190 CNY full-coverage reserve guard')
            if any(e.get('phase')==KIND and e.get('request',{}).get('job_id')==self.context.get('job_id')
                and e.get('request',{}).get('candidate_index')==self.context.get('candidate_index') for e in state['events']):
                raise ProviderError('Duplicate candidate request is forbidden')
            new=[e for e in state['events'] if e.get('phase')==KIND]
            if len(new)>=280 or self.context.get('candidate_index') not in (0,1) or not self.context.get('job_id'):
                raise ProviderError('Request count/candidate identity guard')
            state['spent_cny']=float(money(state['spent_cny'])+amount)
            state['events'].append(dict(request_id=uuid.uuid4().hex,phase=KIND,reserved_cny=float(amount),
                status='reserved',created_at=time.time(),phase_ceiling_cny=TOTAL,review_checkpoint_cny=REVIEW,
                request=dict(request or {},**self.context)))
            atomic_json(self.path,state)
            return len(state['events'])-1

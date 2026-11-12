"""Independent v2 study, secondary credential, proposed 190 total cap."""
import json
from pathlib import Path
import time
import uuid
import f14_study as base
from stbench.billing import ledger_lock,money
from stbench.providers.base import ProviderError
KIND='f14_v2_public_20261112'
TOTAL,REVIEW,SWITCH,BASELINE,HISTORY=190,None,75,81.872503,888
prefix_ok=base.prefix_ok
ReviewPause=base.ReviewPause

class KeySwitch(ProviderError):pass

def authorize(path,before_bytes,plan_sha,at,permission_sha=''):
    path=Path(path);before=json.loads(before_bytes)
    approval=dict(kind=KIND,total_cap_cny=190,review_pause_cny=None,primary_switch_checkpoint_cny=75,
        initial_spent_cny=BASELINE,initial_event_count=HISTORY,previous_limit_cny=190,
        original_ledger_sha256=base.hashlib.sha256(before_bytes).hexdigest(),study_plan_sha256=plan_sha,user_permission_sha256=permission_sha,
        authorization='User requested Agent fixes and immediate paid testing; targeted public follow-up uses existing 190 CNY cap, secondary credential, no 80 pause',authorized_at=at)
    with ledger_lock(path):
        state=json.loads(path.read_text(encoding='utf-8'))
        if 'f14_v2_public_authorization' in state:
            current=state['f14_v2_public_authorization'];assert all(current.get(k)==v for k,v in approval.items() if k!='authorized_at')
            assert state['limit_cny']==190 and prefix_ok(state,before);return current
        if path.read_bytes()!=before_bytes or (state.get('version'),state.get('limit_cny'),state.get('spent_cny'),len(state.get('events',[])),bool(state.get('halted')))!=(3,190,BASELINE,HISTORY,False):
            raise ProviderError('Ledger is not the reviewed 888-event baseline; never reset')
        state['limit_cny']=190;state['f14_v2_public_authorization']=approval
        assert prefix_ok(state,before) and state['spent_cny']==before['spent_cny']
        base.atomic_json(path,state)
    return approval

class StudyBudget(base.StudyBudget):
    def __init__(self,path,plan_sha,active_batch='secondary'):
        self.path=Path(path).resolve();self.phase=KIND;self.limit=190;self.plan_sha=plan_sha
        self.protected_cny=0.;self.context={};self.active_batch=active_batch
        if active_batch not in ('primary','secondary'):raise ProviderError('Unknown credential batch')
        approval=self.read().get('f14_v2_public_authorization',{})
        if (approval.get('study_plan_sha256'),approval.get('total_cap_cny'),approval.get('review_pause_cny'),approval.get('primary_switch_checkpoint_cny'))!=(plan_sha,190,None,75):
            raise ProviderError('Missing explicit matching v2 cap/credential authorization')
    def ceiling(self):return TOTAL
    def admit_job(self,upper):
        state=self.snapshot();projected=money(state['spent_cny'])+money(upper)
        if projected>money(190):raise ProviderError('190 CNY total cap')
        if self.active_batch=='primary' and projected>money(75):raise KeySwitch('Switch before next complete job could exceed cumulative 75 CNY')
    def reserve(self,amount,*,request=None):
        amount=money(amount)
        with ledger_lock(self.path):
            state=self.read();projected=money(state['spent_cny'])+amount
            if projected>money(190):raise ProviderError('190 CNY total cap before send')
            if self.active_batch=='primary' and projected>money(75):raise KeySwitch('Primary request would exceed cumulative 75 CNY; no fee event created')
            if projected+money(self.protected_cny)>money(190):raise ProviderError('190 CNY full-coverage reserve guard')
            context=dict(self.context,study_kind=KIND,credential_batch=self.active_batch)
            if context.get('candidate_index') not in (0,1) or not context.get('job_id'):raise ProviderError('Invalid candidate identity')
            new=[e for e in state['events'] if e.get('phase')==KIND]
            if len(new)>=160 or any(e['request']['job_id']==context['job_id'] and e['request']['candidate_index']==context['candidate_index'] for e in new):
                raise ProviderError('Duplicate candidate or request-count guard')
            state['spent_cny']=float(projected)
            state['events'].append(dict(request_id=uuid.uuid4().hex,phase=KIND,status='reserved',reserved_cny=float(amount),
                created_at=time.time(),phase_ceiling_cny=190,review_checkpoint_cny=None,primary_switch_checkpoint_cny=75,
                request=dict(request or {},**context)))
            base.atomic_json(self.path,state);return len(state['events'])-1

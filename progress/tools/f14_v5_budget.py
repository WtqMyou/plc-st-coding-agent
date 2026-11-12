"""Per-job budget views, serialized reservations and in-flight receipt settlement."""
import hashlib
import json
from pathlib import Path
import threading
import time
import uuid
import f14_v2_study as base
from stbench.billing import ledger_lock,money
from stbench.providers.base import ProviderError

KIND='f14_v5_public_pilot_20261112'
TOTAL=210
BASELINE=108.080587
HISTORY=1141

class CampaignStopped(ProviderError):pass

def authorize(path,before_bytes,plan_sha,proof_sha):
    path=Path(path);before=json.loads(before_bytes)
    with ledger_lock(path):
        current=base.load(path)
        if 'f14_v5_authorization' in current:
            approval=current['f14_v5_authorization']
            assert approval['study_plan_sha256']==plan_sha and approval['proof_sha256']==proof_sha and current['limit_cny']==TOTAL
            assert current['events'][:HISTORY]==before['events']
            return approval
        assert path.read_bytes()==before_bytes,'Ledger changed; do not reset or refund'
        assert (before['limit_cny'],before['spent_cny'],len(before['events']))==(TOTAL,BASELINE,HISTORY)
        assert not before.get('halted'),'Stop for inspection; never silently clear an unknown-charge halt'
        after=json.loads(before_bytes)
        after['f14_v5_authorization']=dict(kind=KIND,total_cap_cny=TOTAL,manual_pause_at_80=False,
            study_plan_sha256=plan_sha,proof_sha256=proof_sha,baseline_sha256=hashlib.sha256(before_bytes).hexdigest(),
            user_instruction='按照你说的做好修改，然后启动付费实验；沿用210元累计上限，六道公共题四组小试',
            historical_events=HISTORY,initial_spent_cny=BASELINE)
        assert after['events']==before['events'] and after['spent_cny']==before['spent_cny']
        base.atomic_json(path,after)
        return after['f14_v5_authorization']

class Coordinator:
    def __init__(self,path,plan,*,baseline=None):
        self.path=Path(path);self.plan=plan;self.lock=threading.RLock();self.stopped=threading.Event()
        self.plan_sha=plan['sha256'];self.baseline=baseline or json.loads(Path(plan['ledger_before']).read_text(encoding='utf-8'))
        self.bounds={j['job_id']:{0:money(j['first_upper_cny']),1:money(j['repair_upper_cny'])} for j in plan['jobs']}
        self.pending={key:dict(value) for key,value in self.bounds.items()}
        state=self.read(allow_halted=True)
        for event in state['events'][HISTORY:]:
            self.pending[event['request']['job_id']].pop(event['request']['candidate_index'],None)
        if state.get('halted'):self.stopped.set()
    def read(self,allow_halted=False):
        state=base.load(self.path)
        if state.get('version')!=3 or state.get('limit_cny')!=TOTAL:raise ProviderError('Budget identity changed')
        approval=state.get('f14_v5_authorization',{})
        assert approval.get('study_plan_sha256')==self.plan_sha and approval.get('total_cap_cny')==TOTAL,'Missing matching frozen-plan authorization'
        if state.get('halted') and not allow_halted:raise CampaignStopped(state['halted'])
        assert state['events'][:HISTORY]==self.baseline['events'],'Historical events changed'
        assert state['recoveries'][:len(self.baseline.get('recoveries',[]))]==self.baseline.get('recoveries',[])
        assert all(state.get(k)==v for k,v in self.baseline.items() if k.endswith('_authorization'))
        new=state['events'][HISTORY:]
        assert len(new)<=48
        keys=[(e['request']['job_id'],e['request']['candidate_index']) for e in new]
        assert len(keys)==len(set(keys))
        for event in new:
            req=event['request'];assert event['phase']==KIND and req['study_plan_sha256']==self.plan_sha
            assert req['job_id'] in self.bounds and req['candidate_index'] in (0,1)
        accounted=money(BASELINE)+sum((money(e.get('accounted_cny',e['reserved_cny'])) for e in new),money(0))
        assert accounted==money(state['spent_cny']) and accounted<=money(TOTAL)
        return state
    def view(self,job_id):return BudgetView(self,job_id)
    def finish(self,job_id):
        with self.lock:self.pending.pop(job_id,None)
    def halt(self,reason,details=None):
        self.stopped.set()
        with self.lock,ledger_lock(self.path):
            state=self.read(allow_halted=True)
            if not state.get('halted'):
                state['halted']=reason
                if details is not None:state['halt_details']=details
                base.atomic_json(self.path,state)

class BudgetView:
    def __init__(self,coordinator,job_id):
        self.coordinator=coordinator;self.path=coordinator.path;self.job_id=job_id
        self.active_batch='secondary';self.context={};self.protected_cny=0
    def snapshot(self):
        with self.coordinator.lock,ledger_lock(self.path):return self.coordinator.read()
    def reserve(self,amount,*,request=None):
        c=self.coordinator;amount=money(amount);idx=self.context.get('candidate_index')
        with c.lock,ledger_lock(self.path):
            if c.stopped.is_set():raise CampaignStopped('Campaign stopped before request send')
            state=c.read();assert self.context.get('job_id')==self.job_id and idx in (0,1)
            if idx not in c.pending.get(self.job_id,{}):raise ProviderError('Duplicate or completed candidate')
            bound=c.pending[self.job_id][idx]
            if amount>bound:raise ProviderError('Frozen request bound exceeded')
            protected=sum((v for key,values in c.pending.items() for i,v in values.items() if (key,i)!=(self.job_id,idx)),money(0))
            if money(state['spent_cny'])+amount+protected>money(TOTAL):raise ProviderError('210 total and remaining-job reservations')
            if len(state['events'])-HISTORY>=48:raise ProviderError('48-request limit')
            state['spent_cny']=float(money(state['spent_cny'])+amount)
            state['events'].append(dict(request_id=uuid.uuid4().hex,phase=KIND,status='reserved',reserved_cny=float(amount),
                created_at=time.time(),phase_ceiling_cny=TOTAL,request=dict(request or {},job_id=self.job_id,candidate_index=idx,
                    credential_batch='secondary',study_plan_sha256=c.plan_sha)))
            base.atomic_json(self.path,state);c.pending[self.job_id].pop(idx)
            return len(state['events'])-1
    def settle(self,index,actual,*,metadata=None):
        c=self.coordinator;actual=money(actual)
        with c.lock,ledger_lock(self.path):
            state=c.read(allow_halted=True);event=state['events'][index]
            assert event['status']=='reserved' and event['request']['job_id']==self.job_id
            state['spent_cny']=float(money(state['spent_cny'])-money(event['reserved_cny'])+actual)
            event.update(status='settled',accounted_cny=float(actual),metadata=metadata or {})
            over=actual>money(event['reserved_cny']) or money(state['spent_cny'])>money(TOTAL)
            if over:state['halted']='Charge exceeded reservation';c.stopped.set()
            base.atomic_json(self.path,state)
            if over:raise ProviderError(state['halted'])
    def halt(self,reason,*,details=None):self.coordinator.halt(reason,details)

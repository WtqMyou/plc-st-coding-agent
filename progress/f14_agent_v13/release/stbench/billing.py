"""One locked, durable campaign ledger; reservations survive crashes and errors."""
from contextlib import contextmanager
from decimal import Decimal, ROUND_CEILING
import hashlib
import json
import math
import os
from pathlib import Path
import time
import uuid
from .evaluation import atomic_json
from .providers.base import ProviderError

PHASES = {"preflight": 5, "development": 20, "final": 65, "retest": 75}

def phase_limits(value=None):
    if value is not None and not isinstance(value,dict):
        raise ProviderError('Phase limits must be a mapping of cumulative ceilings')
    limits=dict(PHASES if value is None else value)
    if (set(limits)!=set(PHASES) or any(isinstance(v,bool) or not isinstance(v,(int,float)) or
        not math.isfinite(v) or v<=0 for v in limits.values()) or
        limits['development']!=20 or limits['final']!=65 or limits['retest']!=75 or
        limits['preflight']>limits['development']):
        raise ProviderError('Invalid cumulative phase limits; preserve development/final/retest reserves and total 75')
    return limits

def money(value):
    if isinstance(value, bool) or not isinstance(value, (float, int, Decimal)) or not math.isfinite(value) or value < 0:
        raise ProviderError("Invalid nonnegative monetary amount")
    return Decimal(str(value)).quantize(Decimal("0.000001"), rounding=ROUND_CEILING)

@contextmanager
def ledger_lock(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.with_suffix(".lock").open("a+b") as lock:
        if lock.tell()==0:lock.write(b"0");lock.flush()
        lock.seek(0)
        if os.name=="nt":
            import msvcrt
            msvcrt.locking(lock.fileno(), msvcrt.LK_LOCK, 1)
        else:
            import fcntl
            fcntl.flock(lock, fcntl.LOCK_EX)
        try:yield
        finally:
            lock.seek(0)
            if os.name=="nt":msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
            else:fcntl.flock(lock, fcntl.LOCK_UN)

class CampaignBudget:
    def __init__(self, path, phase, *, limit=75, phase_caps=None):
        if phase not in PHASES or limit!=75:raise ProviderError("Campaign requires approved 75 CNY allocation")
        self.path,self.phase,self.limit=Path(path).resolve(),phase,limit
        self.phase_caps=phase_limits(phase_caps)
        self.protected_cny=0.
        self.ceiling_override=None
    def ceiling(self):
        return min(self.phase_caps[self.phase],self.ceiling_override) if self.ceiling_override is not None else self.phase_caps[self.phase]
    def read(self, *, allow_halted=False):
        state=json.loads(self.path.read_text(encoding="utf-8")) if self.path.exists() else dict(
            version=3,limit_cny=self.limit,spent_cny=0.,events=[],halted="")
        if state.get("version")!=3 or state.get("limit_cny")!=self.limit:
            raise ProviderError("Budget identity/version mismatch; refusing a reset")
        money(state["spent_cny"])
        if state.get("halted") and not allow_halted:raise ProviderError("Campaign halted: "+state["halted"])
        return state
    def recover_identity(self, evidence_path, expected_model):
        """Resume a diagnosed case-only identity failure without refunding reservations."""
        evidence_path=Path(evidence_path).resolve()
        evidence_bytes=evidence_path.read_bytes()
        evidence=json.loads(evidence_bytes)
        usage=evidence.get('usage',{})
        observed=evidence.get('observed_model')
        if (evidence.get('requested_model')!=expected_model or not isinstance(observed,str)
            or observed.casefold()!=expected_model.casefold() or evidence.get('finish_reason')!='stop'
            or any(isinstance(usage.get(k),bool) or not isinstance(usage.get(k),int) or usage[k]<0
                   for k in ('prompt_tokens','completion_tokens'))):
            raise ProviderError('Identity recovery requires complete matching audit metadata')
        with ledger_lock(self.path):
            state=self.read(allow_halted=True)
            if state.get('halted')!='Unconfirmed upstream result; reservation retained':
                raise ProviderError('This halt is not eligible for identity recovery')
            details=state.get('halt_details')
            if details and (details.get('category')!='model_identity' or details.get('model')!=expected_model):
                raise ProviderError('A non-identity failure cannot use identity recovery')
            audits=[i for i,e in enumerate(state['events']) if e.get('status')=='settled'
                    and e.get('model')==expected_model and e.get('purpose')=='one bounded identity diagnosis'
                    and e.get('metadata')==evidence]
            if not audits:
                raise ProviderError('Identity audit is not linked to a settled ledger event')
            last_unconfirmed=max((i for i,e in enumerate(state['events']) if e.get('status')=='reserved'),default=-1)
            if max(audits)<=last_unconfirmed:
                raise ProviderError('Identity audit predates a newer unconfirmed request')
            backup=self.path.with_name(self.path.stem+'.before_recovery_'+uuid.uuid4().hex+'.json')
            with backup.open('xb') as target:target.write(self.path.read_bytes())
            recovery=dict(previous_halt=state['halted'],spent_cny_unchanged=state['spent_cny'],
                retained_reservations=sum(e['reserved_cny'] for e in state['events'] if e['status']=='reserved'),
                model=expected_model,evidence=str(evidence_path),evidence_sha256=hashlib.sha256(evidence_bytes).hexdigest(),
                backup=str(backup),created_at=time.time())
            state.setdefault('recoveries',[]).append(recovery)
            state['halted']=''
            state.pop('halt_details',None)
            atomic_json(self.path,state)
            return recovery
    def recover_timeout(self,evidence_path,*,request_seconds,validation_path):
        """One diagnosed retry under a validated longer deadline; no old charge is refunded."""
        evidence_path=Path(evidence_path).resolve();evidence_bytes=evidence_path.read_bytes()
        record=json.loads(evidence_bytes);attempts=record.get('attempts',[])
        errors=('Upstream TimeoutError; no automatic retry','Upstream wall deadline exceeded; no automatic retry')
        if (record.get('experiment_kind')!='live' or record.get('stop_reason')!='provider_error'
            or record.get('error') not in errors or len(attempts)!=1):
            raise ProviderError('Timeout recovery requires the original single-request live failure')
        attempt=attempts[0];elapsed=attempt.get('latency_s',0)
        if (attempt.get('provider_error')!=record['error'] or attempt.get('code') or
            attempt.get('prompt_tokens',0) or attempt.get('completion_tokens',0) or
            not isinstance(elapsed,(int,float)) or not math.isfinite(elapsed) or elapsed<=0 or
            not isinstance(request_seconds,(int,float)) or not math.isfinite(request_seconds) or
            not elapsed+1<request_seconds<=600):
            raise ProviderError('A longer bounded timeout and an unconfirmed empty failure are required')
        validation_path=Path(validation_path).resolve();validation_bytes=validation_path.read_bytes()
        validation=json.loads(validation_bytes)
        root=Path(__file__).resolve().parents[1]
        source_hash=hashlib.sha256(b''.join(p.read_bytes() for p in sorted((root/'stbench').rglob('*.py')))).hexdigest()
        if (validation.get('passed') is not True or validation.get('request_seconds')!=request_seconds or
            validation.get('source_sha256')!=source_hash):
            raise ProviderError('Timeout policy needs passing offline evidence for the current source')
        with ledger_lock(self.path):
            state=self.read(allow_halted=True)
            if state.get('halted')!='Unconfirmed upstream result; reservation retained' or not state['events']:
                raise ProviderError('This halt is not eligible for timeout recovery')
            index=len(state['events'])-1;event=state['events'][index];details=state.get('halt_details',{})
            if (event.get('status')!='reserved' or event.get('phase')!='preflight' or not event.get('request_id') or
                not record.get('started_at',float('inf'))<=event.get('created_at',0)<=record.get('finished_at',0) or
                event.get('request',{}).get('model',record['model'])!=record['model'] or
                (details and (details.get('event_index')!=index or details.get('model')!=record['model'] or
                              details.get('category') not in ('request_timeout','upstream_unconfirmed')))):
                raise ProviderError('Timeout evidence does not identify the latest halted reservation')
            if any(r.get('request_id')==event['request_id'] for r in state.get('recoveries',[])):
                raise ProviderError('This timeout reservation was already recovered')
            backup=self.path.with_name(self.path.stem+'.before_timeout_recovery_'+uuid.uuid4().hex+'.json')
            with backup.open('xb') as target:target.write(self.path.read_bytes())
            recovery=dict(reason='validated_longer_timeout',previous_halt=state['halted'],
                request_id=event['request_id'],model=record['model'],spent_cny_unchanged=state['spent_cny'],
                old_elapsed_seconds=elapsed,new_request_seconds=request_seconds,
                evidence=str(evidence_path),evidence_sha256=hashlib.sha256(evidence_bytes).hexdigest(),
                validation=str(validation_path),validation_sha256=hashlib.sha256(validation_bytes).hexdigest(),
                backup=str(backup),created_at=time.time())
            state.setdefault('recoveries',[]).append(recovery);state['halted']='';state.pop('halt_details',None)
            atomic_json(self.path,state);return recovery
    def snapshot(self):
        with ledger_lock(self.path):return self.read()
    def recover_codex_timeout(self,evidence_path,validation_path):
        """Resume once after fixing CLI cancellation; retain the unknown request in full."""
        path=Path(evidence_path).resolve();raw=path.read_bytes();record=json.loads(raw)
        attempts=record.get('attempts',[])
        if (record.get('experiment_kind')!='live' or record.get('provider')!='codex-cli' or
            record.get('stop_reason')!='provider_error' or record.get('error')!='Codex CLI timeout' or
            len(attempts)!=1 or attempts[0].get('provider_error')!='Codex CLI timeout' or
            attempts[0].get('code') or attempts[0].get('prompt_tokens',0) or attempts[0].get('completion_tokens',0)):
            raise ProviderError('CLI recovery requires the original empty single-request Codex timeout')
        validation=Path(validation_path).resolve();proof_bytes=validation.read_bytes();proof=json.loads(proof_bytes)
        root=Path(__file__).resolve().parents[1]
        current=hashlib.sha256(b''.join(p.read_bytes() for p in sorted((root/'stbench').rglob('*.py')))).hexdigest()
        required=('cli_tree_deadline','upstream_failure_aborts_cli','single_upstream_request')
        if (proof.get('passed') is not True or proof.get('source_sha256')!=current or
            proof.get('request_seconds')!=420 or proof.get('cli_seconds')!=450 or
            not all(proof.get('deadline_checks',{}).get(k) is True for k in required)):
            raise ProviderError('CLI recovery needs current passing cancellation and no-retry evidence')
        with ledger_lock(self.path):
            state=self.read(allow_halted=True)
            if state.get('halted')!='Unconfirmed upstream result; reservation retained' or not state['events']:
                raise ProviderError('This halt is not eligible for CLI timeout recovery')
            index=len(state['events'])-1;event=state['events'][index];details=state.get('halt_details',{})
            request=event.get('request',{})
            if (event.get('status')!='reserved' or event.get('phase')!='preflight' or not event.get('request_id') or
                request.get('model')!=record.get('model') or request.get('timeout_seconds')!=420 or
                not record.get('started_at',float('inf'))<=event.get('created_at',0)<=record.get('finished_at',0) or
                details.get('event_index')!=index or details.get('model')!=record.get('model') or
                details.get('category')!='request_timeout' or
                any(r.get('request_id')==event['request_id'] or
                    r.get('evidence_sha256')==hashlib.sha256(raw).hexdigest()
                    for r in state.get('recoveries',[]))):
                raise ProviderError('CLI failure does not identify the latest unrecovered timeout reservation')
            backup=self.path.with_name(self.path.stem+'.before_cli_recovery_'+uuid.uuid4().hex+'.json')
            with backup.open('xb') as f:f.write(self.path.read_bytes())
            recovery=dict(reason='bounded_cli_tree_and_upstream_abort',request_id=event['request_id'],
                model=record['model'],previous_halt=state['halted'],spent_cny_unchanged=state['spent_cny'],
                evidence=str(path),evidence_sha256=hashlib.sha256(raw).hexdigest(),
                validation=str(validation),validation_sha256=hashlib.sha256(proof_bytes).hexdigest(),
                backup=str(backup),created_at=time.time())
            state.setdefault('recoveries',[]).append(recovery);state['halted']='';state.pop('halt_details',None)
            atomic_json(self.path,state)
            return recovery
    def recover_output_limit(self,validation_path,expected_model):
        """One protocol correction after a fully known Chat token overrun; keep all charges."""
        path=Path(validation_path).resolve();raw=path.read_bytes();proof=json.loads(raw)
        root=Path(__file__).resolve().parents[1]
        source_hash=hashlib.sha256(b''.join(p.read_bytes() for p in sorted((root/'stbench').rglob('*.py')))).hexdigest()
        if (proof.get('passed') is not True or proof.get('source_sha256')!=source_hash or
            proof.get('generation_protocols',{}).get(expected_model)!='responses'):
            raise ProviderError('Output-limit recovery requires validated native Responses policy')
        with ledger_lock(self.path):
            state=self.read(allow_halted=True)
            if state.get('halted')!='Charge exceeded reservation' or not state['events']:
                raise ProviderError('This halt is not an output-reservation overrun')
            event=state['events'][-1];request=event.get('request',{});receipt=event.get('metadata',{})
            if (event.get('status')!='settled' or request.get('model')!=expected_model or request.get('protocol')!='chat'
                or str(receipt.get('model','')).casefold()!=expected_model.casefold()
                or receipt.get('completion_tokens',0)<=request.get('max_output_tokens',float('inf'))
                or event.get('accounted_cny',0)<=event.get('reserved_cny',float('inf'))
                or any(r.get('request_id')==event.get('request_id') for r in state.get('recoveries',[]))):
                raise ProviderError('The latest settled event is not the diagnosed Chat output-cap mismatch')
            backup=self.path.with_name(self.path.stem+'.before_output_limit_recovery_'+uuid.uuid4().hex+'.json')
            with backup.open('xb') as f:f.write(self.path.read_bytes())
            recovery=dict(reason='native_responses_total_output_cap',previous_halt=state['halted'],
                model=expected_model,request_id=event['request_id'],spent_cny_unchanged=state['spent_cny'],
                validation=str(path),validation_sha256=hashlib.sha256(raw).hexdigest(),
                backup=str(backup),created_at=time.time())
            state.setdefault('recoveries',[]).append(recovery);state['halted']='';state.pop('halt_details',None)
            atomic_json(self.path,state);return recovery
    def remaining(self):
        return max(0.,float(money(self.ceiling())-money(self.snapshot()["spent_cny"])))
    def reserve(self, amount, *, request=None):
        amount=money(amount)
        with ledger_lock(self.path):
            state=self.read()
            if money(state["spent_cny"])+amount+money(self.protected_cny)>money(self.ceiling()):
                raise ProviderError("Budget coverage guard: stage ceiling or protected first candidates")
            state["spent_cny"]=float(money(state["spent_cny"])+amount)
            state["events"].append(dict(request_id=uuid.uuid4().hex,phase=self.phase,
                reserved_cny=float(amount),status="reserved",created_at=time.time(),phase_ceiling_cny=self.ceiling()))
            if request is not None:state['events'][-1]['request']=request
            atomic_json(self.path,state)
            return len(state["events"])-1
    def settle(self, index, actual, *, metadata=None):
        actual=money(actual)
        with ledger_lock(self.path):
            state=self.read();event=state["events"][index]
            if event["status"]!="reserved":raise ProviderError("Reservation already settled")
            state["spent_cny"]=float(money(state["spent_cny"])-money(event["reserved_cny"])+actual)
            event.update(status="settled",accounted_cny=float(actual),metadata=metadata or {})
            if actual>money(event["reserved_cny"]):state["halted"]="Charge exceeded reservation"
            atomic_json(self.path,state)
            if state["halted"]:raise ProviderError(state["halted"])
    def halt(self, reason, *, details=None):
        # Error text is an internal classification, never an upstream body or key.
        with ledger_lock(self.path):
            state=self.read();state["halted"]=reason
            if details is not None:state['halt_details']=details
            atomic_json(self.path,state)

def canonical_ledger(cfg):
    expected=(Path(cfg["platform_root"])/"evidence"/"dmxapi_budget_75.json").resolve()
    if Path(cfg.get("budget_ledger_path","")).resolve()!=expected or cfg.get("budget_cny")!=75:
        raise ProviderError("All stages must use the canonical shared 75 CNY ledger")
    return expected

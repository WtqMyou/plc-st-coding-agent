"""Versioned authorization over the existing ledger; legacy modules stay frozen."""
import copy
import hashlib
import json
from pathlib import Path
import time
import uuid
from stbench.billing import CampaignBudget, ledger_lock, money
from stbench.evaluation import atomic_json
from stbench.providers.base import ProviderError

TOTAL = 170.
REVIEW = 80.
BASELINE = 39.831304
HISTORY = 451

class ReviewPause(ProviderError):
    pass

def prefix_ok(state, before):
    return (state['events'][:len(before['events'])] == before['events']
            and state.get('recoveries', []) == before.get('recoveries', []))

def migrate(path, before_bytes, plan_sha, at):
    """Idempotent migration; no historical request, reserve or charge is edited."""
    path = Path(path)
    before = json.loads(before_bytes)
    approval = dict(kind='full_r8_20261110b', total_cap_cny=TOTAL, review_pause_cny=REVIEW,
                    initial_spent_cny=BASELINE, initial_event_count=HISTORY,
                    previous_limit_cny=170, original_ledger_sha256=hashlib.sha256(before_bytes).hexdigest(),
                    study_plan_sha256=plan_sha, authorized_at=at,
                    authorization='User approved cumulative 170 CNY and manual review near 80 CNY')
    with ledger_lock(path):
        state = json.loads(path.read_text('utf-8'))
        existing = state.get('full_r8b_authorization')
        if existing:
            for key in approval:
                if key != 'authorized_at' and existing.get(key) != approval[key]:
                    raise ProviderError('Existing authorization differs; no overwrite')
            if state.get('limit_cny') != TOTAL or not prefix_ok(state, before):
                raise ProviderError('Migrated ledger identity/history changed')
            return existing
        if path.read_bytes() != before_bytes:
            raise ProviderError('Ledger changed before authorization; no reset')
        if (before.get('version'), before.get('limit_cny'), before.get('spent_cny'),
                len(before.get('events', [])), bool(before.get('halted'))) != (3,170,BASELINE,HISTORY,True):
            raise ProviderError('Original ledger is not the reviewed baseline')
        if before.get('halted') != 'Provider CSV charge reconciled; awaiting explicit new-batch start':
            raise ProviderError('Expected reconciled restart gate')
        state['halted'] = ''
        state.pop('halt_details',None)
        state['limit_cny'] = TOTAL
        state['full_r8b_authorization'] = approval
        assert prefix_ok(state, before) and state['spent_cny'] == before['spent_cny']
        atomic_json(path, state)
    return approval

class StudyBudget(CampaignBudget):
    """Reuse settlement/halt semantics, with two separate spending gates."""
    def __init__(self, path, plan_sha, review=REVIEW):
        if not REVIEW <= review <= TOTAL:
            raise ProviderError('Unapproved review checkpoint')
        self.path = Path(path).resolve()
        self.phase = 'full_r8_20261110b'
        self.limit = TOTAL
        self.protected_cny = 0.
        self.review = review
        self.plan_sha = plan_sha
        self.context = {}
        state = self.read()
        approval = state.get('full_r8b_authorization', {})
        if (approval.get('study_plan_sha256'),approval.get('total_cap_cny'),approval.get('review_pause_cny')) != (plan_sha,TOTAL,REVIEW):
            raise ProviderError('Missing matching 170/80 authorization')
    def ceiling(self):
        return TOTAL
    def admit_job(self, upper):
        state = self.snapshot()
        if money(state['spent_cny']) + money(upper) > money(self.review):
            raise ReviewPause('Next complete job would exceed the manual review checkpoint')
    def reserve(self, amount, *, request=None):
        amount = money(amount)
        with ledger_lock(self.path):
            state = self.read()
            if money(state['spent_cny']) + amount > money(self.review):
                raise ReviewPause('Next request would exceed the manual review checkpoint')
            if money(state['spent_cny']) + amount + money(self.protected_cny) > money(TOTAL):
                raise ProviderError('Budget coverage guard: preserve all pending requests')
            state['spent_cny'] = float(money(state['spent_cny']) + amount)
            event = dict(request_id=uuid.uuid4().hex,phase=self.phase,reserved_cny=float(amount),
                         status='reserved',created_at=time.time(),phase_ceiling_cny=TOTAL,
                         review_checkpoint_cny=self.review)
            event['request'] = dict(request or {}, **self.context)
            state['events'].append(event)
            atomic_json(self.path,state)
            return len(state['events'])-1

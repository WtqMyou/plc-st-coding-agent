"""Settle only the billed stopped request; preserve its immutable stopped-run evidence."""
import copy
from decimal import Decimal,ROUND_CEILING
import hashlib
import json
from pathlib import Path
import sys
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parent))
import full_r8_study as old
import review_dmxapi_csv_20261110 as csv_review
from stbench.billing import ledger_lock
PENDING='Provider CSV charge reconciled; awaiting explicit new-batch start'
OUT=old.REPO/'progress/evidence/full_r8_reconciliation_20261110'
PRIVATE=Path('E:/PLC_Dev/evidence/full_r8_reconciliation_20261110')

def settled_state(state,review):
    state=copy.deepcopy(state);match=review['match'];amount=review['amounts'];events=state['events']
    assert len(events)==451 and state['limit_cny']==170 and state['version']==3
    event=events[450];original=copy.deepcopy(event)
    assert event['request_id']==match['local_request_id'] and event['status']=='reserved'
    assert event['request']['model']==match['model']=='deepseek-v4-pro-0813'
    assert event['request']['job_id']=='custom_deepseek-v4pro/public-easy-01' and event['request']['candidate_index']==0
    assert state['halted']=='Unconfirmed upstream result; reservation retained'
    assert Decimal(str(state['spent_cny']))==Decimal('40.145743') and Decimal(str(event['reserved_cny']))==Decimal('.430347')
    computed=(Decimal(match['prompt_tokens'])*Decimal('7.11')+Decimal(match['completion_tokens'])*Decimal('21.33'))/Decimal(1000000)
    paid=Decimal(amount['provider_billed_cny'])
    assert paid==Decimal('.115908')==computed.quantize(Decimal('.000001'),rounding=ROUND_CEILING)
    event.update(status='settled',accounted_cny=float(paid),metadata=dict(
        model=match['model'],prompt_tokens=match['prompt_tokens'],completion_tokens=match['completion_tokens'],
        finish_reason='not_recovered',protocol='responses',
        usage=dict(input_tokens=match['prompt_tokens'],output_tokens=match['completion_tokens']),
        basis='Supplier CSV billing reconciliation; generation response/candidate not recovered',
        source_row=match['csv_row'],source_sha256=review['sources'][0]['sha256'],
        provider_request_id_sha256=match['provider_request_id_sha256']))
    state['spent_cny']=float(Decimal(str(state['spent_cny']))-Decimal(str(event['reserved_cny']))+paid)
    state['halted']=PENDING
    old_details=state.get('halt_details')
    state['halt_details']=dict(category='reconciled_charge_missing_response',event_index=450,
                               generation_response_recovered=False,billing_confirmed=True)
    change=dict(kind='provider_csv_settlement_20261110',event_index=450,request_id=event['request_id'],
        before_event=original,after_event=copy.deepcopy(event),before_accounted_cny=40.145743,
        after_accounted_cny=state['spent_cny'],released_reserve_cny=.314439,provider_charge_cny=float(paid),
        previous_halt='Unconfirmed upstream result; reservation retained',previous_halt_details=old_details,
        recovery_authorization='User requested next step after providing and reviewing supplier CSVs',
        review_sha256=old.sha(csv_review.DEST/'review.json'))
    state.setdefault('billing_adjustments',[]).append(change)
    return state,change

def verify_legacy_stop(snapshot):
    import audit_full_r8_stop as stopped
    cfg=old.config();cfg['budget_ledger_path']=str(snapshot)
    with patch.object(stopped.s,'config',return_value=cfg):stopped.check()

def apply():
    assert not PRIVATE.exists() and not OUT.exists(),'Existing settlement must not be overwritten'
    review=csv_review.compute(csv_review.ROOT/'ledger_at_provider_log_review_20261110.json')
    assert review==old.load(csv_review.DEST/'review.json')
    cfg=old.config();path=Path(cfg['budget_ledger_path']);raw=path.read_bytes()
    assert hashlib.sha256(raw).hexdigest()==review['ledger_snapshot_sha256']
    state=old.load(path);updated,change=settled_state(state,review)
    assert updated['events'][:450]==state['events'][:450] and updated['recoveries']==state['recoveries']
    PRIVATE.mkdir(parents=True);before=PRIVATE/'ledger_before.json';before.write_bytes(raw)
    verify_legacy_stop(before)
    with ledger_lock(path):
        assert path.read_bytes()==raw,'Ledger drift before settlement'
        old.atomic_json(path,updated)
    (PRIVATE/'ledger_after.json').write_bytes(path.read_bytes())
    OUT.mkdir(parents=True)
    public=dict(change=change,source_code_sha256=old.sha(__file__),supplier_review_sha256=old.sha(csv_review.DEST/'review.json'),
        before_ledger_sha256=old.sha(before),after_ledger_sha256=old.sha(PRIVATE/'ledger_after.json'),
        original_450_events_preserved=True,original_recoveries_preserved=True,
        generation_response_recovered=False,experiment_restarted=False)
    old.atomic_json(OUT/'settlement.json',public)
    (OUT/'结算说明.md').write_bytes(('''# 首请求费用结算与旧现场保留

根据用户提供CSV的唯一吻合记录，将第451条事件从0.430347元未知预留结算为0.115908元费用，释放0.314439元，累计计入从40.145743元改为39.831304元。原450条事件、恢复记录、原停止报告和现场包未改动。费用证据来源、事件前后值和快照摘要见settlement.json；全量账本快照仅存本地。

供应商计费记录不补造完整响应或候选。旧首题仍未完成。结算后仍设为等待新批次启动，只有用户已明确要求的修复版本通过免费验收、冻结推送后才可开始新请求；不自动重发旧请求。

旧停止验收按结算前快照重现；新的费用核验检查当前账本前451条与结算后快照一致。这保留了两个时点的事实，不修改历史报告去冒充当时已知费用。后续新批次累计170元上限、接近80元暂停继续有效。
''').encode())
    check()

def check():
    public=old.load(OUT/'settlement.json');before=old.load(PRIVATE/'ledger_before.json');after=old.load(PRIVATE/'ledger_after.json')
    assert public['source_code_sha256']==old.sha(__file__)
    assert public['before_ledger_sha256']==old.sha(PRIVATE/'ledger_before.json')
    assert public['after_ledger_sha256']==old.sha(PRIVATE/'ledger_after.json')
    assert before['events'][:450]==after['events'][:450] and before['recoveries']==after['recoveries']
    current=old.load(old.config()['budget_ledger_path'])
    assert current['events'][:451]==after['events'] and current['recoveries']==after['recoveries']
    assert current['billing_adjustments'][:len(after['billing_adjustments'])]==after['billing_adjustments']
    assert after['spent_cny']==39.831304 and after['events'][450]['accounted_cny']==.115908
    verify_legacy_stop(PRIVATE/'ledger_before.json')
    print('PASS billed settlement 0.115908; release 0.314439; baseline 39.831304; old evidence intact')

if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='check':check()
    else:apply()

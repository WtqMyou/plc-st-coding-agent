"""Read supplied provider CSVs and produce a deidentified billing review; no API or ledger writes."""
from collections import Counter,defaultdict
import csv
from datetime import datetime,timezone,timedelta
from decimal import Decimal,ROUND_CEILING
import hashlib
import io
import json
from pathlib import Path
import sys

REPO=Path(__file__).resolve().parents[2]
ROOT=Path('E:/PLC_Dev/evidence/real_experiments/full_r8_20261110')
DEST=REPO/'progress/evidence/full_r8_20261110/provider_log_review_20261110'
NAMES=('DMXAPI日志_20261110_1728.csv','DMXAPI日志_20261110_1727.csv')
LEDGER=Path('E:/PLC_Dev/evidence/dmxapi_budget_75.json')

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def load(p):return json.loads(Path(p).read_text(encoding='utf-8'))
def compute(snapshot):
    sources=[];allrows=[];groups=defaultdict(list)
    for name in NAMES:
        p=Path('C:/Users/27478/Downloads')/name
        rows=list(csv.DictReader(io.StringIO(p.read_text(encoding='utf-8-sig'))))
        sources.append(dict(filename=name,sha256=sha(p),rows=len(rows),
                       earliest=min(r['时间'] for r in rows),latest=max(r['时间'] for r in rows)))
        for line,row in enumerate(rows,2):
            allrows.append((name,line,row));groups[row['Request ID']].append(row)
    matches=[(n,i,r) for n,i,r in allrows if '2026-11-10 17:00:00'<=r['时间']<='2026-11-10 17:05:00']
    assert len(matches)==1,'Time-window match is not unique'
    name,line,row=matches[0];ledger=load(snapshot);event=ledger['events'][-1]
    assert len(ledger['events'])==451 and event['status']=='reserved'
    assert event['request']['job_id']=='custom_deepseek-v4pro/public-easy-01'
    assert row['模型']==event['request']['model'] and row['请求路径']=='/v1/responses' and row['流式']=='是'
    start=datetime.fromtimestamp(event['created_at'],timezone(timedelta(hours=8)))
    logged=datetime.strptime(row['时间'],'%Y-%m-%d %H:%M:%S').replace(tzinfo=start.tzinfo)
    duration_error=abs(Decimal(str((logged-start).total_seconds()))-Decimal(row['耗时(s)']))
    assert duration_error<1 and len(groups[row['Request ID']])==1
    spec=next(m for m in load(REPO/'progress/full_r8/config.json')['models'] if m['model']==row['模型'])
    tokens_in,tokens_out=int(row['提示Tokens']),int(row['补全Tokens'])
    calculated=(Decimal(tokens_in)*Decimal(str(spec['input_cny_per_million']))+Decimal(tokens_out)*Decimal(str(spec['output_cny_per_million'])))/Decimal(1000000)
    billed=Decimal(row['消耗(元)']);assert billed==calculated.quantize(Decimal('.000001'),rounding=ROUND_CEILING)
    reserved=Decimal(str(event['reserved_cny']));spent=Decimal(str(ledger['spent_cny']))
    assert billed<=reserved and spent==Decimal('39.715396')+reserved
    return dict(kind='provider_csv_review_without_ledger_mutation',sources=sources,
                source_code_sha256=sha(__file__),ledger_snapshot_sha256=sha(snapshot),ledger_was_modified=False,
                experiment_restarted=False,external_requests=0,
                match=dict(source_filename=name,csv_row=line,model=row['模型'],time=row['时间'],timezone='Asia/Shanghai',
                    prompt_tokens=tokens_in,completion_tokens=tokens_out,provider_reported_seconds=row['耗时(s)'],
                    elapsed_to_log_seconds=round((logged-start).total_seconds(),6),
                    protocol='responses',streaming=True,provider_response_id_present=bool(row['Response ID']),
                    provider_request_id_sha256=hashlib.sha256(row['Request ID'].encode()).hexdigest(),
                    provider_response_id_sha256=hashlib.sha256(row['Response ID'].encode()).hexdigest(),
                    local_request_id=event['request_id'],
                    basis='Unique time/model/protocol/duration match; not a shared end-to-end trace identifier.'),
                amounts=dict(provider_billed_cny=str(billed),frozen_price_unrounded_cny=str(calculated),
                    retained_local_reserve_cny=str(reserved),potential_release_cny=str(reserved-billed),
                    ledger_accounted_at_review_cny=str(spent),proposed_after_settlement_cny=str(spent-reserved+billed)),
                historical_duplicate_request_id_groups=sum(len(v)>1 for v in groups.values()),
                caveats=['Provider billing is established; full generation response and candidate were not recovered.',
                         'Raw exports contain personal fields and are not published.',
                         'Repeated historical Request IDs have differing business fields; no automatic deduplication or historical refund.',
                         'No settlement, halt clearance, model retry, API switch or claim of completed experiment.'])

def markdown(result):
    a=result['amounts'];m=result['match']
    return f"""# 首次正式请求的提供方日志核对

用户提供两份CSV，原始文件留在Downloads，未修改或上传公开仓库。公开记录仅保留文件摘要、必要的计费字段和标识摘要；不包含令牌名称、用户名、用户ID、IP地址或明文供应商ID。

## 唯一吻合记录

- 来源：{m['source_filename']}第{m['csv_row']}行，时间{m['time']}（北京时间）。
- 请求模型：{m['model']}，流式 /v1/responses。
- 输入{m['prompt_tokens']} token，输出{m['completion_tokens']} token，提供方耗时{m['provider_reported_seconds']}秒。
- 本地请求开始到日志时间相差{m['elapsed_to_log_seconds']}秒，与提供方59秒耗时在1秒以内吻合；此时间窗只出现这一条记录。匹配依据不冒充共享的远程请求编号。

## 费用核对

| 项目 | 元 |
| --- | ---: |
| 提供方记录扣费 | {a['provider_billed_cny']} |
| 按冻结单价计算，向上保留六位小数前 | {a['frozen_price_unrounded_cny']} |
| 当前本地保留预留 | {a['retained_local_reserve_cny']} |
| 若结算本笔，可释放的多余预留 | {a['potential_release_cny']} |
| 核对时账本累计计入 | {a['ledger_accounted_at_review_cny']} |
| 仅结算本笔后的建议累计计入 | {a['proposed_after_settlement_cny']} |

日志中的实扣费用与按冻结单价向上保留六位小数后的0.115908元一致。日志显示这次请求产生了输出用量并已计费，但没有提供可恢复的完整答卷；不能因此把首题改成已生成、已编译或已通过。

## 状态与接续

本次仅补齐计费证据。原451条账本事件、40.145743元累计计入、停止状态、原停止报告与现场包均未改写；未解除停止或发出新模型请求。39.831304元是结算这一笔后的计算值，不是已写入账本的余额。

下一步应以独立可审计入口结算这笔费用并保留变更前快照，改善传输异常类型及响应留痕，再按明确接续指示安排新批次。170元累计上限、接近80元人工暂停约定保留。费用已能核对，故障的具体原因仍不能从这些计费日志确定。

另一份CSV覆盖2026-10-30至10-31，不包含这次17:02的请求。两份历史日志存在5组Request ID重复且业务字段不同，未擅自去重或用日志总额冲销历史预留。
"""

def main():
    snapshot=ROOT/'ledger_at_provider_log_review_20261110.json'
    check=len(sys.argv)>1 and sys.argv[1]=='check'
    if not check:
        assert not DEST.exists() and not snapshot.exists(),'Existing review is never overwritten'
        before=LEDGER.read_bytes();snapshot.write_bytes(before)
        result=compute(snapshot)
        DEST.mkdir(parents=True)
        (DEST/'review.json').write_bytes((json.dumps(result,ensure_ascii=False,indent=2)+'\n').encode())
        (DEST/'核对说明.md').write_bytes(markdown(result).encode())
        assert LEDGER.read_bytes()==before,'Ledger must remain unchanged'
    else:
        result=compute(snapshot)
        assert result==load(DEST/'review.json')
        assert markdown(result).encode()==(DEST/'核对说明.md').read_bytes()
    print('PASS supplier charge 0.115908; proposed release 0.314439; no ledger write or API request')

if __name__=='__main__':main()

"""Verify a copied handoff with standard Python; no Git/E drive/platform/API needed."""
import argparse
from collections import Counter
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(Path(__file__).resolve().parent))
from offline_demo import judge,replay

def load(path):return json.loads(path.read_text(encoding='utf-8'))
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def verify(full=False):
    manifest_path=ROOT/'07_清单指纹/文件清单.json';manifest=load(manifest_path)
    for name,row in manifest['files'].items():
        path=ROOT/name
        assert path.is_file() and path.stat().st_size==row['bytes'] and digest(path)==row['sha256'],name
    print('PASS 文件指纹：'+str(len(manifest['files']))+'个文件')
    records=ROOT/'05_实验记录/最新正式实验';plan=load(records/'study_plan.json');rows=[];attempts=0
    ledger=load(ROOT/'05_实验记录/费用账本/结束账本.json');before=load(ROOT/'05_实验记录/费用账本/开始账本.json')
    assert len(before['events'])==653 and ledger['events'][:653]==before['events']
    assert ledger.get('recoveries',[])==before.get('recoveries',[])
    events=ledger['events'][653:];assert len(events)==235 and all(e['status']=='settled' for e in events)
    linked={(e['request']['job_id'],e['request']['candidate_index']):e for e in events};assert len(linked)==235
    groups=Counter()
    for job in plan['jobs']:
        row=load(records/'jobs'/job['condition']/(job['pid']+'.json'));assert row['job_done'] and 1<=len(row['attempts'])<=2
        assert row['study_plan_sha256']==digest(records/'study_plan.json')
        best=row['attempts'][row['best_attempt']];groups[job['condition']]+=int(best['functional_pass'])
        for index,a in enumerate(row['attempts']):
            e=linked[(job['job_id'],index)];assert Decimal(str(a['cost_cny'])).quantize(Decimal('.000001'),rounding='ROUND_CEILING')==Decimal(str(e['accounted_cny']))
            assert a['actual_model']==e['metadata']['model']
            for field in ('prompt_tokens','completion_tokens'):assert a[field]==e['metadata'][field]
            if a['code']:assert hashlib.sha256(a['code'].encode()).hexdigest()==a['code_hash']
            attempts+=1
        rows.append(row)
    assert len(rows)==140 and attempts==235
    assert groups==Counter({'custom_deepseek-v4pro':15,'codex_deepseek-v4pro':17,'custom_minimax-m27':13,'codex_minimax-m27':11})
    total=Decimal(str(before['spent_cny']))+sum((Decimal(str(e['accounted_cny'])) for e in events),Decimal(0))
    assert total==Decimal(str(ledger['spent_cny']))==Decimal('81.872503')
    print('PASS 140题次、235请求、历史653事件与81.872503元累计关联')
    assert digest(ROOT/'05_实验记录/费用账本/结束账本.json')==load(records/'final_audit.json')['ledger_sha256']
    assert digest(ROOT/'05_实验记录/费用账本/开始账本.json')==plan['initial_ledger_sha256']
    native_ids=set()
    for item in load(ROOT/'07_清单指纹/原生编译索引.json'):
        folder=ROOT/item['package_path'];result=load(folder/'result.json');job=load(folder/'job.json');native=load(folder/'codesys_result.json')
        assert result['status']==native['status']==item['status'] and result['returncode']==0
        assert job['nonce']==native['nonce'] and result['source_sha256']==item['source_sha256']
        native_ids.add(item['native_id'])
    assert len(native_ids)==108
    print('PASS 108个真实编译工程、nonce和源程序指纹关联')
    if full:
        reference=judge(dict(mode='references'));assert reference['tasks']==35 and reference['cases']==946
        print('PASS 35题参考程序离线功能复验946/946')
        for case in ('native','functional','formal'):replay(case,verify=True)
    print('PASS 交接包可独立读取和核验，未调用生成模型')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--full',action='store_true');args=parser.parse_args();verify(args.full)

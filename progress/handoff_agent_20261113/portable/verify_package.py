"""Verify the complete relocated handoff with only Python's standard library."""
import argparse
from collections import Counter
from decimal import Decimal,ROUND_CEILING
import hashlib
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(Path(__file__).resolve().parent))
from offline_demo import judge,replay

def load(p):return json.loads(p.read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def money(value):return Decimal(str(value)).quantize(Decimal('.000001'),rounding=ROUND_CEILING)

def verify(full=False):
    manifest=load(ROOT/'07_清单指纹/文件清单.json')
    for name,row in manifest['files'].items():
        path=ROOT/name
        assert path.is_file() and path.stat().st_size==row['bytes'] and sha(path)==row['sha256'],name
    print('PASS 文件指纹：',len(manifest['files']))
    source=ROOT/'01_原工程';latest=ROOT/'05_实验记录/最新正式实验'
    plan=load(latest/'study_plan.json');import_plan=load(latest/'导入20题来源/study_plan.json')
    for prefix,entries in [(source,plan['files']),(source/'progress/f14_agent_v14/release',plan['release_files'])]:
        for rel,digest in entries.items():assert sha(prefix/rel)==digest,rel
    print('PASS 冻结源码、题库及裁判指纹')
    end=load(ROOT/'05_实验记录/费用账本/结束账本.json');before=load(ROOT/'05_实验记录/费用账本/开始账本.json')
    assert len(before['events'])==1702 and len(end['events'])==1965
    assert end['events'][:1702]==before['events']
    assert end.get('recoveries',[])[:len(before.get('recoveries',[]))]==before.get('recoveries',[])
    for k,v in before.items():
        if k.endswith('_authorization'):assert end[k]==v
    assert money(before['spent_cny'])+sum((money(e.get('accounted_cny',e['reserved_cny'])) for e in end['events'][1702:]),Decimal(0))==money(end['spent_cny'])==Decimal('211.178859')
    assert sha(ROOT/'05_实验记录/费用账本/开始账本.json')==plan['initial_ledger_sha256']
    origins=load(ROOT/'07_清单指纹/题次来源索引.json');assert len(origins)==140
    linked={(e['phase'],e.get('request',{}).get('job_id'),e.get('request',{}).get('candidate_index')):(i,e) for i,e in enumerate(end['events'])}
    package=source/'progress/f14_agent_v14';sys.path.insert(0,str(source/'agent_dev_r9_stage3'));sys.path.insert(0,str(package))
    from v13_repairs import apply
    from v13_formatting import normalize
    counts=Counter();calls=0;unknown=[];passed_cases=0;first=Counter();cohorts=Counter()
    for origin in origins:
        record=load(ROOT/origin['record']);assert sha(ROOT/origin['record'])==origin['record_sha256']
        assert record['job_done'] and 1<=len(record['attempts'])<=4
        expected_plan=sha(latest/'导入20题来源/study_plan.json') if origin['imported_v13'] else sha(latest/'study_plan.json')
        assert record['study_plan_sha256']==expected_plan
        best=record['attempts'][record['best_attempt']];counts[origin['condition']]+=bool(best['functional_pass'])
        first[origin['condition']]+=bool(record['attempts'][0]['functional_pass']);passed_cases+=best['tests_passed']
        cohorts[(origin['condition'],origin['network_wait_seconds'])]+=1
        folder=(ROOT/origin['record']).parent;pid=origin['pid']
        for a in record['attempts']:
            _,event=linked[(origin['phase'],record['job_id'],a['idx'])];calls+=1
            assert (folder/(pid+f'.request_{a["idx"]+1:02}.json')).exists()
            if event['status']=='reserved':
                assert a.get('provider_error') and not a['code']
                assert money(a['unknown_cost_reservation_cny'])==money(event['reserved_cny'])
                unknown.append(event)
            else:
                assert event['status']=='settled' and money(event['accounted_cny'])==money(a['cost_cny'])
                assert event['metadata']['model']==a['actual_model']
                for key in ('prompt_tokens','completion_tokens'):assert event['metadata'][key]==a[key]
                assert (folder/(pid+f'.response_{a["idx"]+1:02}.json')).exists()
            if a.get('code'):
                raw=(folder/(pid+f'.raw_candidate_{a["idx"]+1:02}.st')).read_bytes().decode('utf-8')
                assert hashlib.sha256(raw.encode()).hexdigest()==a['raw_source_sha256']
                normalized,edits=normalize(raw);assert normalized==a['code'] and edits==a['format_edits']
                assert sha(folder/(pid+f'.candidate_{a["idx"]+1:02}.st'))==a['code_hash']
                if a.get('model_patch',{}).get('mode') in ('model_exact_edits','model_replacement'):
                    patch=load(folder/(pid+f'.model_patch_{a["idx"]+1:02}.json'))
                    base=(folder/(pid+f'.patch_base_{a["idx"]+1:02}.st')).read_bytes().decode('utf-8')
                    expanded,_=apply(patch['raw_model_text'],base);assert expanded==raw
    assert calls==306 and passed_cases==3008
    assert counts==Counter({'custom_deepseek-v4pro':33,'codex_deepseek-v4pro':34,'custom_minimax-m27':13,'codex_minimax-m27':11})
    assert first==Counter({'custom_deepseek-v4pro':24,'codex_deepseek-v4pro':27,'custom_minimax-m27':8,'codex_minimax-m27':8})
    assert len(unknown)==8 and sum((money(e['reserved_cny']) for e in unknown),Decimal(0))==Decimal('2.643027')
    for c in ('custom_minimax-m27','codex_minimax-m27'):assert cohorts[(c,420)]==9 and cohorts[(c,900)]==26
    print('PASS 140题次、306请求、精确补丁重放、33/34/13/11成绩与8条保留预留')
    native=load(ROOT/'07_清单指纹/原生编译索引.json');unique=set()
    for item in native:
        folder=ROOT/item['package_path'];result=load(folder/'result.json');job=load(folder/'job.json');compiler=load(folder/'codesys_result.json')
        assert result['status']==compiler['status']==item['status']
        assert result['source_sha256']==item['source_sha256']
        assert job['nonce']==compiler['nonce']
        unique.add(item['native_id'])
    assert len(unique)==manifest['counts']['native_builds']
    print('PASS 真实原生编译工程及nonce关联：',len(unique))
    if full:
        reference=judge(dict(mode='references'));assert reference['tasks']==35 and reference['cases']==946
        print('PASS 最新裁判35题参考功能复验946/946')
        for case in ('native','functional','formal','formal_legacy'):replay(case,verify=True)
    print('PASS 标准库离线交接验收；模型调用0次')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--full',action='store_true');args=parser.parse_args();verify(args.full)

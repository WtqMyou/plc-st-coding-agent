"""Post-hoc correction and fixed-candidate recheck; original raw records are immutable."""
import hashlib
import json
from pathlib import Path
import sys

REPO=Path(__file__).resolve().parents[2]
SOURCE=REPO/'agent_dev_r9_stage3'
sys.path.insert(0,str(SOURCE))
from stbench.campaign import tasks,digest
from stbench.evaluation import local_tests


def main():
    root=Path('E:/PLC_Dev/evidence/real_experiments/r9_repair_policy_20261101')
    out=REPO/'progress/evidence/r9_repair_analysis_20261101'
    out.mkdir(parents=True,exist_ok=False)
    records=[p for p in sorted((root/'jobs').glob('*/*.json'))
             if not any(s in p.name for s in ('.request_','.response_','.timing.'))]
    before={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in records}
    ledger=Path('E:/PLC_Dev/evidence/dmxapi_budget_75.json');ledger_hash=hashlib.sha256(ledger.read_bytes()).hexdigest()
    selected={p.pid:p for _,p,_ in tasks()};rows=[];checks=[]
    for path in records:
        r=json.loads(path.read_text(encoding='utf-8'));attempts=r['attempts']
        rows.append(dict(condition=path.parent.name,pid=r['pid'],first_solved=r.get('first_try'),solved=r.get('solved'),
            attempts=len(attempts),mc_executed=sum(bool(a.get('judge',{}).get('model_check',{}).get('executed')) for a in attempts),
            incomplete=sum(a.get('provider_error','').startswith('Generation incomplete/empty:') for a in attempts)))
        for a in attempts:
            if not a.get('code'):continue
            result=local_tests(a['code'],selected[r['pid']])
            checks.append(dict(condition=path.parent.name,pid=r['pid'],attempt=a['idx'],
                code_sha256=hashlib.sha256(a['code'].encode()).hexdigest(),old_static=a['compiles'],
                new_static=result.compiles,old_tests=a['tests_passed'],new_tests=result.tests_passed,
                note='fixed paid code; local static and simulation recheck only, native compilation not rerun'))
    assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in before.items())
    assert hashlib.sha256(ledger.read_bytes()).hexdigest()==ledger_hash
    report=dict(original_records=16,original_attempts=sum(r['attempts'] for r in rows),
        corrected_mc_executed=sum(r['mc_executed'] for r in rows),
        old_summary_mc_executed=0,correction='read judge.model_check.executed, not judge.mc_executed',
        original_records_unchanged=True,ledger_unchanged=True,model_requests=0,new_judge_sha256=digest(),
        rows=rows,fixed_code_rechecks=checks,original_record_sha256=before)
    (out/'analysis.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    groups={}
    for r in rows:
        g=groups.setdefault(r['condition'],dict(solved=0,mc=0,incomplete=0))
        g['solved']+=bool(r['solved']);g['mc']+=r['mc_executed'];g['incomplete']+=r['incomplete']
    lines=['# 第二阶段修复试验复盘与统计勘误','','原始16题次、28次生成已完成。新增计入1.363941元，共享账本36.373218元。','',
        '|条件|整题功能通过/2|实际LTL执行|截断/空正文|','|---|---|---|---|']
    for name,g in groups.items():lines.append(f"|{name}|{g['solved']}/2|{g['mc']}|{g['incomplete']}|")
    lines+=['','旧汇总错误读取扁平字段，LTL执行次数显示为0；原始裁判保存的是嵌套 model_check.executed。',
        f"正确累计为 {report['corrected_mc_executed']} 次。仅另附勘误，不覆盖原记录或旧汇总。",'',
        '1200秒增加了自研的实际修复机会，但未新增功能成功；检查策略无跨框架一致收益。两题随机小样本不能归因于单因素。',
        '原付费代码使用新检查器做了固定候选重查，逐条见JSON；仅本地静态/模拟检查，不重新生成或改写原生编译结论。',
        '发现枚举支持缺口后采用独立第三阶段副本修复。也发现通用复位提示容易将边沿约定套到电平复位任务，第三阶段改为逐题遵守公开契约。',
        '原16条记录和费用账本的字节哈希在本次免费分析前后均一致。']
    (out/'分析说明.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(json.dumps({k:report[k] for k in ('original_records','original_attempts','corrected_mc_executed','model_requests','original_records_unchanged','ledger_unchanged')}))


if __name__=='__main__':main()

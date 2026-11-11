"""Free round-trip, reference and directed feedback checks for the candidate F1.4 bridge."""
import json
from collections import Counter
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import full_r8b_study as s
sys.path.insert(0,str(s.REPO/'progress/f14_candidate'))
import bridge
ROOT=Path('E:/PLC_Dev/evidence/incoming_reviews/f14_bridge_preflight_20261111_v2')
RELEASE=bridge.ROOT/'release'

def source(pid):
    path,=list(RELEASE.glob('datasets/*/'+pid+'.json'))
    return (path.parent/'tests'/(pid+'.reference.st')).read_text(encoding='utf-8')

def main():
    cfg=s.config();ledger=Path(cfg['budget_ledger_path']);before=ledger.read_bytes()
    assert not ROOT.exists(),'Preserve completed or stopped preflight'
    ROOT.mkdir(parents=True);rows=[]
    for path in sorted(RELEASE.glob('datasets/*/*.json')):
        pid=path.stem;expected=s.load(path);result=bridge.evaluate(source(pid),pid)
        row=result['result']
        assert row['compiles'] and row['tests_passed']==row['tests_total']==len(expected['test_cases']),pid
        actual_ids=[c['tc_id'] for c in row['cases']]
        expected_ids=[c['tc_id'] for c in expected['test_cases']]
        assert Counter(actual_ids)==Counter(expected_ids) and len(set(actual_ids))==len(actual_ids),pid
        groups={}
        for c in expected['test_cases']:
            groups.setdefault((c.get('group',''),c.get('mode') or expected.get('case_mode') or 'single'),[]).append(c['tc_id'])
        for ids in groups.values():assert [i for i in actual_ids if i in set(ids)]==ids,pid
        assert ledger.read_bytes()==before
        rows.append(dict(pid=pid,passed=row['tests_passed'],total=row['tests_total'],worker_metadata=row['evidence_metadata']))
        s.atomic_json(ROOT/'reference_rows.json',rows)
        print('REFERENCE',pid,row['tests_passed'],'/',row['tests_total'],flush=True)
    assert len(rows)==35 and sum(r['total'] for r in rows)==946
    fixtures=[]
    def check(label,pid,code,mode='functional'):
        result=bridge.evaluate(code,pid,mode)
        s.atomic_json(ROOT/(label+'.json'),result)
        assert ledger.read_bytes()==before
        fixtures.append(dict(label=label,pid=pid,mode=mode,compiles=result['result']['compiles'],
            passed=result['result']['tests_passed'],total=result['result']['tests_total'],status=result['verification_status'],feedback=result['feedback']))
        return result
    # Independent groups, real elapsed time and old-state snapshots are covered by all 946 reference cases.
    fifo=source('public-hard-04')
    sticky=fifo.replace('status := 16#0000;','IF reset OR enEdge OR deEdge THEN status := 16#0000; END_IF;')
    assert sticky!=fifo
    bad=check('fifo-sticky','public-hard-04',sticky)
    assert bad['result']['tests_passed']==30 and bad['result']['tests_total']==31
    assert '期望' not in bad['feedback'] and '实际' not in bad['feedback']
    recipe=RELEASE/'review/fixtures/agent_9772562/recipe.st'
    bad=check('recipe-concurrent','public-hard-03',recipe.read_text(encoding='utf-8'))
    assert bad['result']['tests_passed']==19 and bad['result']['tests_total']==21
    # Both successful handling and error reporting on concurrent recipe requests remain allowed.
    serial=source('public-hard-03')
    for text in ('IF dEdge THEN','IF mEdge THEN'):serial=serial.replace(text,text+'\n  IF recipeAdded THEN hitIdx := freeIdx; END_IF;')
    assert check('recipe-alternative','public-hard-03',serial)['result']['tests_passed']==21
    pump=source('public-easy-04');wrong=pump.replace('+ TIME_TO_LTIME(CycleTime)','+ LTIME#1ms')
    assert wrong!=pump
    timed=check('pump-fixed-period','public-easy-04',wrong)
    assert timed['result']['compiles'] and timed['result']['tests_passed']<20
    formal=check('fifo-reference-formal','public-hard-04',fifo,'bounded')
    assert formal['verification_status']=='bounded_pass'
    timed=check('pump-formal-unmodeled-clock','public-easy-04',pump,'bounded')
    assert timed['verification_status']=='inconclusive'
    assert timed['result']['evidence_metadata']['classification']=='unsupported_modeling'
    s.atomic_json(ROOT/'completion.json',dict(reference_tasks=35,reference_cases=946,passed=True,model_calls=0,
        fixtures=fixtures,ledger_sha256=s.sha(ledger),controller_sha256=s.sha(__file__),bridge_sha256=s.sha(bridge.__file__),
        worker_sha256=s.sha(bridge.ROOT/'judge_worker.py'),completed_at=s.stamp()))
    print('PASS isolated F1.4 bridge and directed feedback controls',flush=True)

if __name__=='__main__':main()

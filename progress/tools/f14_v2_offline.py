"""Exercise all frozen initial routes against a local fixture, never a paid API."""
import hashlib
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import f14_v2_study as s
from stbench.codex_baseline import ResponsesGateway

def main():
    cfg=s.config();root=Path(cfg['campaign_root']);ledger=Path(cfg['budget_ledger_path']);before=ledger.read_bytes()
    assert not root.exists(),'Existing evidence must be retained; do not repeat preparation'
    root.mkdir(parents=True);rows=[]
    s.atomic_json(root/'offline_preparation.json',dict(external_requests=0,cli_identity=s.old.old.cli_identity(),controller_sha256=s.sha(__file__),ledger_sha256=s.sha(ledger)))
    for n,(pid,task) in enumerate(s.tasks().items()):
        path,=s.RELEASE.glob('datasets/*/tests/'+pid+'.reference.st');code=path.read_text(encoding='utf-8')
        for arm in s.old.ORDERS[n%4]:
            framework,modelid=s.old.ARMS[arm];model=next(m for m in cfg['models'] if m['id']==modelid)
            fixture=s.old.old.Fixture(model['model'],code);job=dict(pid=pid)
            if framework=='custom':response=fixture.generate(s.messages(job))
            else:
                with ResponsesGateway(provider=fixture,model=fixture.model) as gateway:
                    response=s.InitialTextCodexProvider(gateway,model=fixture.model,work_root=root/'offline_cli',mock=True,timeout=65).generate(s.messages(job))
            assert s.extract_code(response.text).strip()==code.strip()
            actual=fixture.messages
            assert any(m['role']=='user' and m['content']==s.messages(job)[1]['content'] for m in actual)
            assert all(code.strip() not in m['content'] for m in actual),'Reference answer must never enter model input'
            result=s.run_stage(code,pid,'functional',30)
            assert result['result']['tests_passed']==result['result']['tests_total']==len(task['test_cases']),(pid,result)
            condition=framework+'_'+modelid
            s.atomic_json(root/'offline_requests'/condition/(pid+'.json'),dict(messages=actual,model=model['model'],external_requests=0))
            size=len(json.dumps(actual,ensure_ascii=False).encode())
            first=s.money(((size+6144)*model['input_cny_per_million']+16384*model['output_cny_per_million'])/1e6)
            repair=s.money((65536*model['input_cny_per_million']+16384*model['output_cny_per_million'])/1e6)
            rows.append(dict(job_id=condition+'/'+pid,first_upper_cny=float(first),repair_upper_cny=float(repair),upstream_message_bytes=size,
                messages_sha256=hashlib.sha256(json.dumps(actual,ensure_ascii=False).encode()).hexdigest(),tests_passed=len(task['test_cases']),fixture_requests=1,external_requests=0))
            assert ledger.read_bytes()==before
            s.atomic_json(root/'offline_routes.json',dict(completed=False,rows=rows,external_requests=0,repair_fake_routes=12))
        print('LOCAL CHANNELS',pid,len(rows),'/140',flush=True)
    s.atomic_json(root/'offline_routes.json',dict(completed=True,rows=rows,external_requests=0,real_cli_invocations=70,repair_fake_routes=12,ledger_sha256=s.sha(ledger)))
    total=sum((s.money(r['first_upper_cny'])+s.money(r['repair_upper_cny']) for r in rows),s.money(0))
    print('PASS 140 local channels; reserve',float(total),flush=True)

if __name__=='__main__':main()

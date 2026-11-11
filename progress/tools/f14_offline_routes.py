"""140 local-only initial-candidate channel checks; no paid provider is instantiated."""
import hashlib
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import full_r8b_study as s
sys.path.insert(0,str(s.REPO/'progress/f14_candidate'))
import bridge
from codex_transport import InitialTextCodexProvider
from stbench.codex_baseline import ResponsesGateway

ROOT=Path('E:/PLC_Dev/evidence/incoming_reviews/f14_offline_routes_20261111')
SYSTEM='Return one complete ST implementation. Follow the user requirements and interface exactly. Do not change task inputs or outputs.'

def main():
    cfg=s.config();ledger=Path(cfg['budget_ledger_path']);before=ledger.read_bytes()
    assert not ROOT.exists(),'Preserve existing channel evidence'
    ROOT.mkdir(parents=True)
    prompts=s.load(bridge.ROOT/'release/agent_inputs.json');rows=[]
    s.atomic_json(ROOT/'preparation.json',dict(kind='offline communication checks; final study strategy not frozen',
        model_calls_to_external_services=0,ledger_sha256=s.sha(ledger),controller_sha256=s.sha(__file__),
        adapter_sha256=s.sha(s.REPO/'progress/f14_candidate/codex_transport.py'),cli_identity=s.old.cli_identity(),
        draft_common_system=SYSTEM))
    for n,(pid,entry) in enumerate(prompts.items()):
        path,=list((bridge.ROOT/'release').glob('datasets/*/'+pid+'.json'))
        override=bridge.ROOT/'compatibility/reference_overrides'/(pid+'.reference.st')
        code=(override if override.exists() else path.parent/'tests'/(pid+'.reference.st')).read_text(encoding='utf-8')
        arms=s.ORDERS[n%4]
        for arm in arms:
            framework,modelid=s.ARMS[arm];model=next(m for m in cfg['models'] if m['id']==modelid)
            messages=[dict(role='system',content=SYSTEM),dict(role='user',content=entry['user'])]
            assert all(code.strip() not in m['content'] for m in messages)
            fixture=s.old.Fixture(model['model'],code)
            if framework=='custom':response=fixture.generate(messages)
            else:
                with ResponsesGateway(provider=fixture,model=fixture.model) as gateway:
                    response=InitialTextCodexProvider(gateway,model=fixture.model,work_root=ROOT/'cli',mock=True,timeout=60).generate(messages)
            assert response.text.strip()==code.strip()
            assert any(m['role']=='user' and m['content']==entry['user'] for m in fixture.messages),'Initial user text changed'
            assert all(code.strip() not in m['content'] for m in fixture.messages)
            result=bridge.evaluate(response.text,pid)
            assert result['result']['tests_passed']==result['result']['tests_total']==len(s.load(path)['test_cases'])
            actual=fixture.messages;signature=hashlib.sha256(json.dumps(actual,ensure_ascii=False).encode()).hexdigest()
            condition=framework+'_'+modelid;folder=ROOT/'requests'/condition;folder.mkdir(parents=True,exist_ok=True)
            s.atomic_json(folder/(pid+'.json'),dict(model=fixture.model,messages=actual,external_requests=0))
            rows.append(dict(job_id=condition+'/'+pid,model=fixture.model,generation_protocol=model['generation_protocol'],
                upstream_messages_sha256=signature,upstream_message_bytes=len(json.dumps(actual,ensure_ascii=False).encode()),
                exact_initial_user_sha256=entry['sha256'],code_source='separate_reference_compatibility_patch' if override.exists() else 'official_reference',
                tests_passed=result['result']['tests_passed'],gateway_fixture_requests=1,external_requests=0))
            assert ledger.read_bytes()==before
            s.atomic_json(ROOT/'routes.json',dict(completed=False,external_requests=0,rows=rows))
        print('CHANNELS',pid,len(rows),'/140',flush=True)
    assert len(rows)==140 and len({r['job_id'] for r in rows})==140
    s.atomic_json(ROOT/'routes.json',dict(completed=True,external_requests=0,rows=rows,
        conditions=4,tasks_per_condition=35,assertions_per_condition=946,paid_model_generation_performed=False,
        real_cli_invocations=70,ledger_sha256=s.sha(ledger),completed_at=s.stamp()))
    print('PASS 140 local-only channels, including 70 real CLI invocations; original task text preserved',flush=True)

if __name__=='__main__':main()

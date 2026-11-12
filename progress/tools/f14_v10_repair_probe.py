"""Free real-CLI repair-context sizing on long public and self-built tasks."""
import hashlib
import json
from pathlib import Path
import f14_v10_core as s
from stbench.codex_baseline import ResponsesGateway

def main():
    cfg=s.config();root=Path(cfg['campaign_root']);ledger=Path(cfg['budget_ledger_path']);before=ledger.read_bytes()
    assert not (root/'prepared.json').exists();rows=[]
    routes={r['job_id']:r for r in s.load(root/'offline_routes.json')['rows']}
    # Synthetic candidate and synthetic observed trace, never a reference solution or hidden assertion.
    code='FUNCTION_BLOCK FB VAR local_probe:INT;END_VAR (* '+('mock context padding '*430)+' *) local_probe:=0;END_FUNCTION_BLOCK'
    feedback='Complete synthetic public-input prefix for transport testing only: '+json.dumps([dict(inputs=dict(probeInput=i),observed_outputs=dict(probeOutput=i),cycles=1) for i in range(210)])
    for pid in ('self-hard-06','public-hard-05'):
        for framework,mid in s.old.ARMS:
            model=next(m for m in cfg['models'] if m['id']==mid);fixture=s.old.old.Fixture(model['model'],code)
            messages=s.messages(dict(pid=pid))+[dict(role='assistant',content=code),dict(role='user',content=feedback)]
            if framework=='custom':response=fixture.generate(messages)
            else:
                with ResponsesGateway(provider=fixture,model=fixture.model) as gateway:
                    response=s.InitialTextCodexProvider(gateway,model=fixture.model,work_root=root/'offline_repair_cli',mock=True,timeout=65).generate(messages)
            assert s.extract_code(response.text)==code
            actual=fixture.messages;size=len(json.dumps(actual,ensure_ascii=False).encode());job=framework+'_'+mid+'/'+pid
            upper=s.money(((size+4096)*model['input_cny_per_million']+16384*model['output_cny_per_million'])/1e6)
            assert upper<=s.money(routes[job]['repair_upper_cny']),(job,size,upper)
            s.atomic_json(root/'offline_repair_requests'/framework/ mid/(pid+'.json'),dict(messages=actual,external_model_calls=0))
            rows.append(dict(job_id=job,upstream_message_bytes=size,upper_cny=float(upper),frozen_bound_cny=routes[job]['repair_upper_cny'],
                message_sha256=hashlib.sha256(json.dumps(actual,ensure_ascii=False).encode()).hexdigest(),fixture_requests=1,external_model_calls=0))
    assert ledger.read_bytes()==before
    s.atomic_json(root/'offline_repair_routes.json',dict(passed=True,rows=rows,local_channels=8,real_cli_invocations=4,ledger_unchanged=True,external_model_calls=0))
    print('PASS 8 long repair-context routes; no external model calls',flush=True)

if __name__=='__main__':main()

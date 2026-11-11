"""Route recorded real CODESYS errors into four offline repair channels."""
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

ROOT=Path('E:/PLC_Dev/evidence/incoming_reviews/f14_native_feedback_routes_20261111')
OUT=s.REPO/'progress/evidence/f14_native_feedback_20261111'
NATIVE=Path('E:/PLC_Dev/evidence/incoming_reviews/f14_native_preflight_20261111/summary.json')

def inputs():
    pid='public-easy-02';release=bridge.ROOT/'release'
    before=(release/'datasets/public/tests'/(pid+'.reference.st')).read_text(encoding='utf-8')
    after=(bridge.ROOT/'compatibility/reference_overrides'/(pid+'.reference.st')).read_text(encoding='utf-8')
    row=next(r for r in s.load(NATIVE)['rows'] if r['pid']==pid)
    assert row['native_status']=='failed' and hashlib.sha256(before.encode()).hexdigest()==row['source_sha256']
    feedback='CODESYS native compilation failed:\n'+'\n'.join(row['native']['diagnostics'])
    messages=[dict(role='system',content='Return a complete ST implementation without changing the user interface.'),
        dict(role='user',content=s.load(release/'agent_inputs.json')[pid]['user']),dict(role='assistant',content=before),
        dict(role='user',content=feedback[:4000]+'\n修复并返回完整代码，保持题面接口。')]
    assert all(after.strip() not in m['content'] for m in messages)
    return after,feedback,messages,row

def check():
    cfg=s.config();done=s.load(ROOT/'completion.json');after,feedback,messages,row=inputs()
    assert done['passed'] and done['external_requests']==0 and len(done['rows'])==4
    assert s.sha(__file__)==done['controller_sha256']
    assert s.sha(bridge.ROOT/'codex_transport.py')==done['adapter_sha256']
    assert s.sha(cfg['budget_ledger_path'])==done['ledger_sha256']
    assert s.sha(NATIVE)==done['native_summary_sha256']
    for item in done['rows']:
        saved=s.load(ROOT/(item['condition']+'.json'))
        assert any(feedback in m['content'].replace('\r\n','\n') for m in saved['messages'])
        assert all(after.strip() not in m['content'] for m in saved['messages'])
        assert saved['external_requests']==0 and saved['model']==item['model']
    for name,digest in s.load(OUT/'evidence_manifest.json')['files'].items():assert s.sha(OUT/name)==digest
    assert s.load(OUT/'completion.json')==done
    return done

def main():
    assert not ROOT.exists() and not OUT.exists(),'Preserve previous evidence'
    cfg=s.config();ledger=Path(cfg['budget_ledger_path']);before=ledger.read_bytes()
    ROOT.mkdir(parents=True);after,feedback,messages,native=inputs();rows=[]
    for framework,modelid in s.ARMS:
        model=next(m for m in cfg['models'] if m['id']==modelid);fixture=s.old.Fixture(model['model'],after)
        if framework=='custom':response=fixture.generate(messages)
        else:
            with ResponsesGateway(provider=fixture,model=fixture.model) as gateway:
                response=InitialTextCodexProvider(gateway,model=fixture.model,work_root=ROOT/'cli',mock=True,timeout=60).generate(messages)
        assert response.text.strip()==after.strip()
        assert any(feedback in m['content'].replace('\r\n','\n') for m in fixture.messages)
        result=bridge.evaluate(response.text,'public-easy-02')['result']
        assert result['tests_passed']==result['tests_total']==11
        assert ledger.read_bytes()==before
        condition=framework+'_'+modelid
        s.atomic_json(ROOT/(condition+'.json'),dict(model=model['model'],messages=fixture.messages,external_requests=0))
        rows.append(dict(condition=condition,model=model['model'],source='recorded real CODESYS diagnostics',functional_passed=11))
    s.atomic_json(ROOT/'completion.json',dict(passed=True,rows=rows,external_requests=0,real_cli_invocations=2,
        live_controller_connected=False,model_performance_test=False,ledger_sha256=s.sha(ledger),
        controller_sha256=s.sha(__file__),adapter_sha256=s.sha(bridge.ROOT/'codex_transport.py'),
        native_summary_sha256=s.sha(NATIVE),completed_at=s.stamp()))
    OUT.mkdir(parents=True)
    import shutil
    for file in ROOT.glob('*.json'):shutil.copyfile(file,OUT/file.name)
    s.atomic_json(OUT/'evidence_manifest.json',dict(files={p.name:s.sha(p) for p in OUT.glob('*.json')}))
    check()

if __name__=='__main__':
    if sys.argv[1:]==['--check']:check()
    elif not sys.argv[1:]:main()
    else:raise SystemExit('Usage: f14_native_feedback_routes.py [--check]')
    print('PASS actual native compilation diagnostics reached all four local repair channels; external requests 0')

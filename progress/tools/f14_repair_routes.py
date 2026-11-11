"""Free compile/function/formal repair-message routing checks, not paid model experiments."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import full_r8b_study as s
sys.path.insert(0,str(s.REPO/'progress/f14_candidate'))
import bridge
from codex_transport import InitialTextCodexProvider
from stbench.codex_baseline import ResponsesGateway
ROOT=Path('E:/PLC_Dev/evidence/incoming_reviews/f14_repair_routes_20261111')

def main():
    cfg=s.config();ledger=Path(cfg['budget_ledger_path']);before=ledger.read_bytes()
    assert not ROOT.exists();ROOT.mkdir(parents=True)
    release=bridge.ROOT/'release';prompts=s.load(release/'agent_inputs.json')
    p='public-easy-01';good=(release/'datasets/public/tests'/(p+'.reference.st')).read_text(encoding='utf-8')
    bad=good.replace('END_FUNCTION_BLOCK','Completion_Light := ;\nEND_FUNCTION_BLOCK')
    compile_feedback=bridge.evaluate(bad,p)['feedback']
    q='public-hard-04';fifo=(release/'datasets/public/tests'/(q+'.reference.st')).read_text(encoding='utf-8')
    sticky=fifo.replace('status := 16#0000;','IF reset OR enEdge OR deEdge THEN status := 16#0000; END_IF;')
    function_feedback=bridge.evaluate(sticky,q)['feedback']
    proc=subprocess.run([sys.executable,'-B','-X','utf8',str(bridge.ROOT/'feedback_probe.py')],capture_output=True,text=True,encoding='utf-8',timeout=15)
    assert proc.returncode==0,proc.stderr
    probe=json.loads(proc.stdout);s.atomic_json(ROOT/'synthetic_formal_probe.json',probe)
    cases=[dict(kind='compile',user=prompts[p]['user'],bad=bad,good=good,feedback=compile_feedback),
           dict(kind='functional',user=prompts[q]['user'],bad=sticky,good=fifo,feedback=function_feedback),
           dict(kind='formal-synthetic',user=probe['user'],bad=probe['bad_source'],good=probe['good_source'],feedback=probe['feedback'])]
    rows=[]
    for case in cases:
        assert '期望' not in case['feedback'] and '实际' not in case['feedback']
        messages=[dict(role='system',content='Return a complete ST implementation without changing the user interface.'),
            dict(role='user',content=case['user']),dict(role='assistant',content=case['bad']),
            dict(role='user',content=case['feedback'][:4000]+'\n修复并返回完整代码，保持题面接口。')]
        for framework,modelid in s.ARMS:
            model=next(m for m in cfg['models'] if m['id']==modelid)
            fixture=s.old.Fixture(model['model'],case['good'])
            if framework=='custom':response=fixture.generate(messages)
            else:
                with ResponsesGateway(provider=fixture,model=fixture.model) as gateway:
                    response=InitialTextCodexProvider(gateway,model=fixture.model,work_root=ROOT/'cli',mock=True,timeout=60).generate(messages)
            assert response.text.strip()==case['good'].strip()
            expected_feedback=case['feedback'].replace('\r\n','\n')
            assert any(expected_feedback in m['content'].replace('\r\n','\n') for m in fixture.messages)
            assert any(case['bad'].replace('\r\n','\n') in m['content'].replace('\r\n','\n') for m in fixture.messages)
            assert ledger.read_bytes()==before
            label=case['kind']+'_'+framework+'_'+modelid
            s.atomic_json(ROOT/(label+'.json'),dict(messages=fixture.messages,expected_feedback=case['feedback'],external_requests=0))
            rows.append(dict(label=label,feedback_kind=case['kind'],framework=framework,model=model['model'],external_requests=0))
        print('REPAIR_CHANNEL',case['kind'],len(rows),'/12',flush=True)
    s.atomic_json(ROOT/'completion.json',dict(passed=True,rows=rows,synthetic_formal_probe_excluded_from_scores=True,external_requests=0,
        ledger_sha256=s.sha(ledger),controller_sha256=s.sha(__file__),adapter_sha256=s.sha(bridge.ROOT/'codex_transport.py'),completed_at=s.stamp()))
    print('PASS 12 local repair channels with all three feedback types',flush=True)

if __name__=='__main__':main()

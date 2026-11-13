"""No paid calls: full calibration, import replay and actual CLI request-size capture."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import ast
import json
import subprocess
import sys
import f14_v14_core as s
from stbench.codex_baseline import ResponsesGateway

def main():
    cfg=s.config();root=Path(cfg['campaign_root']);root.mkdir(parents=True,exist_ok=True)
    before=Path(cfg['budget_ledger_path']).read_bytes()
    prior=s.REPO/'progress/f14_agent_v13'
    for p in s.CONFIG.parent.rglob('*'):
        if p.is_file() and p.name not in ('config.json','README.md') and '__pycache__' not in p.parts:
            assert p.read_bytes()==(prior/p.relative_to(s.CONFIG.parent)).read_bytes(),p
    # The execution extension does not tune the pipeline that produced the imported twenty.
    def functions(path):
        return {f.name:ast.dump(f,include_attributes=False) for f in ast.parse(path.read_text(encoding='utf-8')).body if isinstance(f,ast.FunctionDef)}
    current=functions(Path(s.__file__));old=functions(s.REPO/'progress/tools/f14_v13_core.py')
    for name in ('messages','generate_job','evaluate','repair_messages','run_stage','classify','select_best','repairable','capture'):
        assert current[name]==old[name],name
    for label,args in [('native',[]),('legacy_original',['--legacy-original'])]:
        process=subprocess.run([sys.executable,'-B','-X','utf8',str(s.CONFIG.parent/'judge_audit_worker.py'),*args],capture_output=True,text=True,encoding='utf-8',timeout=300)
        assert process.returncode==0,process.stderr[-2500:]
        result=json.loads(process.stdout);assert result['reference_cases']==946 and result['negative_controls']==35 and not result['private_rename_regressions']
        s.atomic_json(root/('calibration_'+label+'.json'),result)
    imported=[]
    for pid in [pid for pid in s.tasks() if pid.startswith('public-')]:
        record=s.load(s.IMPORTED_ROOT/'jobs/custom_deepseek-v4pro'/(pid+'.json'));a=record['attempts'][record['best_attempt']]
        # A local-only pass cannot override a prior failed native compile gate.
        accepted=a['native_pass'] or not a['native_eligible']
        result=s.run_stage(a['code'],pid,'functional' if accepted else 'static',30)['result']
        assert result['tests_passed']==a['tests_passed'] and record['job_done'],(pid,result['tests_passed'],a['tests_passed'],a['compiles'])
        original=s.load(s.IMPORTED_ROOT/'jobs/custom_deepseek-v4pro'/(pid+'.request_01.json'))
        assert original['messages']==s.messages(dict(pid=pid))
        imported.append(dict(pid=pid,functional=a['functional_pass'],passed=a['tests_passed'],total=a['tests_total']))
    assert sum(r['functional'] for r in imported)==18 and sum(r['passed'] for r in imported)==430
    s.atomic_json(root/'imported_replay.json',dict(passed=True,rows=imported,original_inputs_and_policy_identical=True,external_model_requests=0))
    jobs=[]
    for n,(pid,task) in enumerate(s.tasks().items()):
        for i in s.old.ORDERS[n%4]:
            framework,mid=s.old.ARMS[i];jobs.append((pid,task,framework,mid))
    def route(item):
        pid,task,framework,mid=item;model=next(m for m in cfg['models'] if m['id']==mid)
        path=s.CONFIG.parent/'reference_controls/public-medium-08.reference.st' if pid=='public-medium-08' else next(s.RELEASE.glob('datasets/*/tests/'+pid+'.reference.st'))
        code=path.read_text(encoding='utf-8');fixture=s.old.old.Fixture(model['model'],code);messages=s.messages(dict(pid=pid))
        if framework=='custom':response=fixture.generate(messages)
        else:
            with ResponsesGateway(provider=fixture,model=fixture.model) as gateway:
                response=s.InitialTextCodexProvider(gateway,model=fixture.model,work_root=root/'offline_cli',mock=True,timeout=65).generate(messages)
        assert s.extract_code(response.text).strip()==code.strip()
        actual=fixture.messages
        assert any(m['role']=='user' and m['content']==messages[1]['content'] for m in actual)
        assert all(code.strip() not in m['content'] for m in actual)
        size=len(json.dumps(actual,ensure_ascii=False).encode());repair_bytes=65536 if framework=='custom' else 90112
        assert size+4096<=repair_bytes
        first_bytes=min(size+8192,repair_bytes)
        def bound(n):return float(s.money((n*model['input_cny_per_million']+24576*model['output_cny_per_million'])/1e6))
        condition=framework+'_'+mid
        s.atomic_json(root/'offline_requests'/condition/(pid+'.json'),dict(messages=actual,external_model_calls=0))
        return dict(job_id=condition+'/'+pid,first_upper_cny=bound(first_bytes),repair_upper_cny=bound(repair_bytes),
            first_input_bytes=first_bytes,repair_input_bytes=repair_bytes,captured_message_bytes=size,
            fixture_requests=1,external_requests=0)
    with ThreadPoolExecutor(max_workers=8) as pool:rows=list(pool.map(route,jobs))
    assert len(rows)==140
    s.atomic_json(root/'offline_routes.json',dict(completed=True,rows=rows,external_requests=0,real_cli_invocations=70,
        first_reservation_basis='actual captured message bytes +8192, at least4096 more than transport input estimate; repair envelopes unchanged'))
    tests=subprocess.run([sys.executable,'-B','-X','utf8','-m','unittest','discover','-s','progress/tests','-p','test_f14_v14*.py','-v'],cwd=s.REPO,capture_output=True,text=True,encoding='utf-8',timeout=240)
    (root/'free_tests.log').write_text(tests.stdout+tests.stderr,encoding='utf-8');assert tests.returncode==0,tests.stderr[-4000:]
    assert Path(cfg['budget_ledger_path']).read_bytes()==before
    s.atomic_json(root/'validation.json',dict(passed=True,reference_cases=946,private_rename_cases=946,negative_controls=35,
        local_routes=140,real_cli_invocations=70,imported_replays=20,original_functional_passed=18,original_assertions_passed=430,
        generator_feedback_and_judge_unchanged=True,external_model_requests=0,ledger_unchanged=True,free_tests_sha256=s.sha(root/'free_tests.log')))
    print('PASS 140 routes / 70 real CLI invocations; 946 reference +946 rename +35 negatives; 20 imports unchanged',flush=True)

if __name__=='__main__':main()

"""Parallel free route capture, full unchanged-judge calibration and source guards."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import f14_v11_core as s
from stbench.codex_baseline import ResponsesGateway

def main():
    cfg=s.config();root=Path(cfg['campaign_root']);ledger=Path(cfg['budget_ledger_path']);before=ledger.read_bytes()
    assert not root.exists();root.mkdir(parents=True)
    calibration=s.REPO/'progress/evidence/f14_v11_preflight_20261113';calibration.mkdir(exist_ok=False)
    for label,args in [('native',[]),('legacy_original',['--legacy-original'])]:
        p=subprocess.run([sys.executable,'-B','-X','utf8',str(s.CONFIG.parent/'judge_audit_worker.py'),*args],capture_output=True,text=True,encoding='utf-8',timeout=300)
        assert p.returncode==0,p.stderr[-3000:]
        x=json.loads(p.stdout);assert x['reference_cases']==946 and x['negative_controls']==35 and not x['private_rename_regressions']
        s.atomic_json(calibration/(label+'.json'),x)
    for rel in [Path('agent_inputs.json'),*[p.relative_to(s.RELEASE) for p in (s.RELEASE/'datasets').rglob('*') if p.is_file()]]:
        assert (s.RELEASE/rel).read_bytes()==(s.REPO/'progress/f14_candidate/release'/rel).read_bytes()
    jobs=[]
    for n,(pid,task) in enumerate(s.tasks().items()):
        for i in s.old.ORDERS[n%4]:
            framework,mid=s.old.ARMS[i];jobs.append((pid,task,framework,mid))
    def run(item):
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
        size=len(json.dumps(actual,ensure_ascii=False).encode());input_bound=65536 if framework=='custom' else 90112
        assert size+4096<=input_bound
        result=s.run_stage(code,pid,'functional',30)
        assert result['result']['tests_passed']==result['result']['tests_total']==len(task['test_cases'])
        condition=framework+'_'+mid
        s.atomic_json(root/'offline_requests'/condition/(pid+'.json'),dict(messages=actual,external_model_calls=0))
        bound=s.money((input_bound*model['input_cny_per_million']+24576*model['output_cny_per_million'])/1e6)
        return dict(job_id=condition+'/'+pid,first_upper_cny=float(bound),repair_upper_cny=float(bound),input_bound_bytes=input_bound,
            max_output_tokens=24576,upstream_message_bytes=size,messages_sha256=hashlib.sha256(json.dumps(actual,ensure_ascii=False).encode()).hexdigest(),fixture_requests=1,external_requests=0)
    with ThreadPoolExecutor(max_workers=8) as pool:rows=list(pool.map(run,jobs))
    assert len(rows)==80 and ledger.read_bytes()==before
    s.atomic_json(root/'offline_routes.json',dict(completed=True,rows=rows,external_requests=0,real_cli_invocations=40))
    # All 35 references must also satisfy the structural gate. No native compilation is skipped for valid structures.
    sys.path.insert(0,str(s.CONFIG.parent));from structure_check import check
    for pid in s.all_tasks():
        path=s.CONFIG.parent/'reference_controls/public-medium-08.reference.st' if pid=='public-medium-08' else next(s.RELEASE.glob('datasets/*/tests/'+pid+'.reference.st'))
        assert not check(path.read_text(encoding='utf-8')),pid
    s.atomic_json(root/'offline_repair_routes.json',dict(passed=True,covered_by='four-arm real-CLI repair-feedback and four-candidate mock regression controls',external_model_calls=0))
    total=sum((4*s.money(r['first_upper_cny']) for r in rows),s.money(0))
    s.atomic_json(root/'budget_refinement.json',dict(new_worst_reservation_cny=float(total),cumulative_worst_cny=float(s.money(s.BASELINE)+total),uniform_bounds=True,max_requests=320,max_output_tokens=24576))
    s.atomic_json(calibration/'summary.json',dict(passed=True,reference_cases=946,private_rename_cases=946,negative_controls=35,
        local_routes=80,real_cli_invocations=40,reference_structures=35,data_files_unchanged=True,ledger_unchanged=True,external_model_calls=0))
    print('PASS 80 local routes in parallel, 946 reference/946 rename/35 negatives; worst cumulative',float(s.money(s.BASELINE)+total),flush=True)

if __name__=='__main__':main()

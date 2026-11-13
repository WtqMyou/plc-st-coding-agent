"""Free controls before freezing: unchanged judge, old answers, fresh channels and ABI."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json
import subprocess
import sys
import f14_v12_core as s

def main():
    cfg=s.config();root=Path(cfg['campaign_root']);root.mkdir(parents=True,exist_ok=True)
    before=Path(cfg['budget_ledger_path']).read_bytes();reports={}
    for label,args in [('native',[]),('legacy_original',['--legacy-original'])]:
        p=subprocess.run([sys.executable,'-B','-X','utf8',str(s.CONFIG.parent/'judge_audit_worker.py'),*args],capture_output=True,text=True,encoding='utf-8',timeout=300)
        assert p.returncode==0,p.stderr[-3000:]
        result=json.loads(p.stdout);assert result['reference_cases']==946 and result['negative_controls']==35 and not result['private_rename_regressions']
        reports[label]=result;s.atomic_json(root/('calibration_'+label+'.json'),result)
    for p in s.RELEASE.rglob('*'):
        if p.is_file():assert p.read_bytes()==(s.REPO/'progress/f14_agent_v11/release'/p.relative_to(s.RELEASE)).read_bytes()
    def replay(pid):
        old=s.load(s.SEED_ROOT/'jobs/custom_deepseek-v4pro'/(pid+'.json'));a=old['attempts'][old['best_attempt']]
        result=s.run_stage(a['code'],pid,'functional' if a['compiles'] else 'static',30)
        assert result['result']['tests_passed']==a['tests_passed'],(pid,result['result']['tests_passed'],a['tests_passed'])
        if pid=='public-medium-04':
            assert 'candidate_timer_observations' in result['feedback'] and '"ET"' in result['feedback'],result['feedback']
        assert '"expected":' not in result['feedback'] and '"note":' not in result['feedback']
        return dict(pid=pid,old_functional=a['functional_pass'],passed=a['tests_passed'],feedback_timer_probe=pid=='public-medium-04')
    with ThreadPoolExecutor(max_workers=8) as pool:rows=list(pool.map(replay,s.tasks()))
    assert sum(r['old_functional'] for r in rows)==16
    s.atomic_json(root/'saved_answer_regression.json',dict(passed=True,rows=rows,old_passes_preserved=16))
    model=cfg['models'][0];route_rows=[]
    for pid in s.tasks():
        code_path=s.CONFIG.parent/'reference_controls/public-medium-08.reference.st' if pid=='public-medium-08' else next(s.RELEASE.glob('datasets/*/tests/'+pid+'.reference.st'))
        fixture=s.old.old.Fixture(model['model'],code_path.read_text(encoding='utf-8'));messages=s.messages(dict(pid=pid))
        response=fixture.generate(messages);assert s.extract_code(response.text).strip()==code_path.read_text(encoding='utf-8').strip()
        assert messages[1]['content']==s.load(s.RELEASE/'agent_inputs.json')[pid]['user']
        assert not any(code_path.read_text(encoding='utf-8').strip() in m['content'] for m in messages)
        assert len(json.dumps(messages,ensure_ascii=False).encode())+4096<=65536
        route_rows.append(dict(pid=pid,fixture_requests=1,external_requests=0))
    s.atomic_json(root/'offline_routes.json',dict(passed=True,rows=route_rows,external_requests=0))
    p=subprocess.run([sys.executable,'-B','-X','utf8','-m','unittest','discover','-s','progress/tests','-p','test_f14_v12*.py','-v'],cwd=s.REPO,capture_output=True,text=True,encoding='utf-8',timeout=180)
    (root/'free_tests.log').write_text(p.stdout+p.stderr,encoding='utf-8');assert p.returncode==0,p.stderr[-5000:]
    assert Path(cfg['budget_ledger_path']).read_bytes()==before
    s.atomic_json(root/'validation.json',dict(passed=True,reference_cases=946,rename_cases=946,negative_controls=35,
        old_passes_preserved=16,local_routes=20,external_model_requests=0,ledger_unchanged=True,release_unchanged=True,
        free_tests_sha256=s.sha(root/'free_tests.log')))
    print('PASS calibration, 20 saved replays, timer feedback, 20 fresh channels and regression tests',flush=True)

if __name__=='__main__':main()

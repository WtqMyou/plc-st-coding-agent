"""Free native-semantics calibration, legacy reference preservation and frozen-answer diagnostics."""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import shutil
import subprocess
import sys
from types import SimpleNamespace
import f14_v6_core as s
ROOT=s.REPO/'progress/evidence/f14_v6_preflight_20261112'
NATIVE=Path('E:/PLC_Dev/evidence/incoming_reviews/f14_v6_native_controls_20261112')


def run(args,timeout=300):
    process=subprocess.run([sys.executable,'-B','-X','utf8',*args],cwd=s.REPO,capture_output=True,text=True,encoding='utf-8',timeout=timeout)
    assert process.returncode==0,process.stderr[-5000:]
    return process


def main():
    cfg=s.config();ledger=Path(cfg['budget_ledger_path']);before=ledger.read_bytes();ROOT.mkdir(parents=True,exist_ok=True)
    for mode,args in [('native',[]),('legacy_original',['--legacy-original'])]:
        process=run([str(s.CONFIG.parent/'judge_audit_worker.py'),*args])
        result=json.loads(process.stdout)
        assert result['reference_cases']==946 and result['negative_controls']==35 and not result['private_rename_regressions']
        s.atomic_json(ROOT/(mode+'_calibration.json'),result)
    assert s.load(NATIVE/'completion.json')['passed']
    for label in ('positive','negative'):
        result=s.load(NATIVE/label/'result.json')
        assert result['native_execution'] and not result['cleanup_errors']
        assert result['status']==('passed' if label=='positive' else 'test_failed')
        for name in ('job.json','result.json','FB.st','PLC_PRG.st','stdout.log','stderr.log'):
            target=ROOT/'native_controls'/label/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(NATIVE/label/name,target)
    shutil.copyfile(NATIVE/'completion.json',ROOT/'native_controls/completion.json')
    control=s.CONFIG.parent/'reference_controls/public-medium-08.reference.st'
    code=control.read_text(encoding='utf-8');formatted,edits=s.normalize(code)
    local=s.run_stage(formatted,'public-medium-08','functional',30)
    assert local['result']['tests_passed']==local['result']['tests_total']==14
    backend=s.old.old.support.CodesysBackend(cfg);backend.timeout=120
    native=backend.compile(formatted,SimpleNamespace(pid='v6-reference-control-medium08')).to_dict()
    assert native['status']=='passed',native
    s.atomic_json(ROOT/'ipv4_control.json',dict(source_sha256=s.sha(control),normalization_edits=edits,native=native,functional=local))
    # Independently replay the paid V5 answers. Diagnostic-only: no old score or candidate changes.
    previous=s.REPO/'progress/evidence/f14_v5_public_pilot_20261112/operational_restarts/string_byte_20261112/effective_jobs'
    tasks=[]
    for path in previous.glob('*/*.json'):
        record=s.load(path)
        for attempt in record['attempts']:
            tasks.append((record,attempt))
    assert len(tasks)==42
    def replay(item):
        record,attempt=item
        row=dict(job_id=record['job_id'],candidate=attempt['idx'],original_functional=attempt['functional_pass'],original_passed=attempt['tests_passed'],native_pass=attempt['native_pass'])
        if not attempt.get('code') or not attempt['native_pass']:
            return dict(row,evaluation='not_evaluated_native_failed_or_no_code')
        result=s.run_stage(attempt['code'],record['pid'],'functional',30)
        return dict(row,evaluation='free_recheck',result=result)
    with ThreadPoolExecutor(max_workers=4) as pool:replayed=list(pool.map(replay,tasks))
    s.atomic_json(ROOT/'v5_frozen_answer_diagnostics.json',dict(diagnostic_only=True,new_model_calls=0,original_candidates_unchanged=True,rows=replayed))
    pristine=s.REPO/'progress/f14_candidate/release'
    for rel in [Path('agent_inputs.json'),*[p.relative_to(s.RELEASE) for p in (s.RELEASE/'datasets').rglob('*') if p.is_file()]]:
        assert (s.RELEASE/rel).read_bytes()==(pristine/rel).read_bytes(),rel
    process=run(['-m','unittest','discover','-s','progress/tests','-p','test_f14_v6.py','-v'])
    (ROOT/'regression_tests.log').write_text(process.stdout+process.stderr,encoding='utf-8')
    import f14_v5_core as prior
    prior.verify(prior.config())
    assert ledger.read_bytes()==before
    s.atomic_json(ROOT/'summary.json',dict(passed=True,reference_cases=946,private_rename_cases=946,negative_controls=35,
        original_legacy_reference_cases=946,native_control_reference_overrides=['public-medium-08'],
        original_task_files_unchanged=True,original_v5_frozen=True,local_native_simulator_controls=True,
        full_replay_groups_without_prefix_truncation=True,declared_contract_checks=True,max_candidates=4,
        v5_frozen_attempts_rechecked=42,ledger_unchanged=True,ledger_sha256=s.sha(ledger),external_model_calls=0))
    print('PASS V6 free calibration: native/legacy 946 cases, value-copy controls, replay checks, frozen old evidence; zero API calls',flush=True)


if __name__=='__main__':main()

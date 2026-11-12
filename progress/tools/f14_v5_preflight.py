"""Free full-corpus calibration and actual native dialect positive/negative controls."""
import json
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace
import f14_v5_core as s

ROOT=s.REPO/'progress/evidence/f14_v5_preflight_20261112'
PROBE='''TYPE ST_V5_Probe : STRUCT value : INT; END_STRUCT END_TYPE
FUNCTION_BLOCK FB_V5Probe
VAR_INPUT go:BOOL; mode:INT; END_VAR
VAR_OUTPUT rec:ST_V5_Probe; END_VAR
VAR state:(STATE_IDLE,STATE_ACTIVE); END_VAR
IF go THEN state:=STATE_ACTIVE; END_IF;
CASE mode OF
1: IF go THEN
CASE state OF
STATE_IDLE: rec.value:=3;
STATE_ACTIVE: rec.value:=7;
END_CASE;
END_IF;
2: rec.value:=9;
END_CASE;
END_FUNCTION_BLOCK'''


def command(args,timeout=300):
    p=subprocess.run([sys.executable,'-B','-X','utf8',*args],cwd=s.REPO,
                     capture_output=True,text=True,encoding='utf-8',timeout=timeout)
    assert p.returncode==0,p.stderr[-5000:]
    return p


def main():
    cfg=s.config();ledger=Path(cfg['budget_ledger_path']);before=ledger.read_bytes()
    ROOT.mkdir(parents=True,exist_ok=True)
    result=command([str(s.CONFIG.parent/'judge_audit_worker.py')])
    calibration=json.loads(result.stdout)
    assert calibration['reference_cases']==946 and calibration['negative_controls']==35
    assert not calibration['private_rename_regressions']
    s.atomic_json(ROOT/'judge_calibration.json',calibration)
    rows=[]
    for pid,task in s.all_tasks().items():
        ref,=s.RELEASE.glob('datasets/*/tests/'+pid+'.reference.st')
        formatted,edits=s.normalize(ref.read_text(encoding='utf-8'))
        result=s.run_stage(formatted,pid,'functional',30)
        static=s.run_stage(formatted,pid,'static',30)
        assert static['result']['compiles'],(pid,static)
        assert result['result']['tests_passed']==len(task['test_cases']),(pid,result)
        rows.append(dict(pid=pid,passed=result['result']['tests_passed'],reference_sha256=s.sha(ref),format_edits=edits))
    s.atomic_json(ROOT/'all_reference_replay.json',dict(rows=rows,passed=946,model_calls=0))
    # These candidates were already accepted by native CODESYS. Re-evaluate without generating new answers.
    historical=[]
    oldroot=Path('E:/PLC_Dev/evidence/real_experiments/f14_v3_parallel_20261112')
    for condition in ('custom_deepseek-v4pro','custom_minimax-m27'):
        record=s.load(oldroot/'jobs'/condition/'public-hard-02.json')
        candidates=[a for a in record['attempts'] if a.get('code') and a.get('native_pass')]
        assert candidates
        attempt=candidates[-1];code,_=s.normalize(attempt['code'])
        static=s.run_stage(code,'public-hard-02','static',30)
        assert static['result']['compiles'],(condition,static)
        functional=s.run_stage(code,'public-hard-02','functional',30)
        assert functional['result']['compiles'] and not functional['result'].get('mc_error')
        historical.append(dict(condition=condition,source_sha256=s.hashlib.sha256(code.encode()).hexdigest(),static=static,functional=functional))
    s.atomic_json(ROOT/'historical_native_accepted_recheck.json',historical)
    source,edits=s.normalize(PROBE)
    request=dict(source=source,scans=[dict(go=True,mode=1),dict(go=False,mode=2)],outputs=['rec'])
    process=subprocess.run([sys.executable,'-B','-X','utf8',str(s.CONFIG.parent/'runtime_probe.py')],
        input=json.dumps(request),capture_output=True,text=True,encoding='utf-8',timeout=15)
    assert process.returncode==0,process.stderr
    probe=json.loads(process.stdout)
    assert probe['ok'] and probe['scans']==[dict(rec=dict(value=7)),dict(rec=dict(value=9))],probe
    s.atomic_json(ROOT/'runtime_probe.json',probe)
    native=[]
    for label,code,expected in [('positive',source,'passed'),('negative',source.replace('rec.value:=7','undeclared_v5_bad:=7'),'failed')]:
        backend=s.old.old.support.CodesysBackend(cfg);backend.timeout=120
        result=backend.compile(code,SimpleNamespace(pid='v5-control-'+label)).to_dict()
        assert result['status']==expected,(label,result)
        (ROOT/(label+'.st')).write_text(code,encoding='utf-8')
        native.append(dict(label=label,expected_native_status=expected,result=result))
    s.atomic_json(ROOT/'native_controls.json',native)
    # Ensure the problem, references, tests, agent input and formal specifications are byte-identical.
    pristine=s.REPO/'progress/f14_candidate/release'
    for rel in [Path('agent_inputs.json'),*[(p.relative_to(s.RELEASE)) for p in (s.RELEASE/'datasets').rglob('*') if p.is_file()]]:
        assert (s.RELEASE/rel).read_bytes()==(pristine/rel).read_bytes(),rel
    for pattern in ('test_f14_v4_diagnostics.py','test_f14_v5.py'):
        p=command(['-m','unittest','discover','-s','progress/tests','-p',pattern,'-v'])
        (ROOT/(pattern+'.log')).write_text(p.stdout+p.stderr,encoding='utf-8')
    import f14_v3_core as original
    original.verify(original.config())
    assert ledger.read_bytes()==before
    s.atomic_json(ROOT/'summary.json',dict(passed=True,reference_tasks=35,reference_cases=946,
        renamed_cases=946,negative_controls=35,native_positive_and_negative_controls=True,
        historical_native_accepted_candidates_rechecked=2,original_v3_frozen=True,original_task_files_unchanged=True,
        ledger_unchanged=True,ledger_sha256=s.sha(ledger),external_model_calls=0))
    print('PASS V5 calibration: 946 references + 946 private renames + 35 negative controls; native controls; no paid calls',flush=True)


if __name__=='__main__':main()

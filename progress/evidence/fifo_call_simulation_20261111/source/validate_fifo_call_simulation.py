"""Build the supplied P1 calling program and run local CODESYS simulation, with one negative control."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from uuid import uuid4
sys.path.insert(0,str(Path(__file__).resolve().parent))
import full_r8b_study as s
from stbench.platforms import split_st

SOURCE=Path('E:/PLC_Dev/evidence/incoming_reviews/stbench_f14p1_20261111/source/STBench_F1.4-P1')
ROOT=Path('E:/PLC_Dev/evidence/incoming_reviews/fifo_call_simulation_20261111_v3')
WORKER=Path(__file__).with_name('codesys_fifo_call_worker.py')

def main():
    cfg=s.config();live=Path(cfg['campaign_root']);s.verify(live)
    s.old.support.no_other_runner(cfg)
    ledger_before=Path(cfg['budget_ledger_path']).read_bytes()
    assert not ROOT.exists(),'Preserve earlier run; no implicit overwrite or repeat'
    ROOT.mkdir(parents=True)
    (ROOT/'cache').mkdir()
    fb=(SOURCE/'platform_review/portable/public-hard-04.dint-array.st').read_text(encoding='utf-8')
    program=(SOURCE/'platform_review/portable/PLC_PRG.st').read_text(encoding='utf-8')
    backend=s.old.support.CodesysBackend(dict(cfg,platform_root=str(ROOT)))
    identity=s.old.support.CodesysBackend(cfg).identity()
    assert identity==s.load(live/'native_preflight.json')['codesys']['positive']['platform_identity']
    s.atomic_json(ROOT/'baseline.json',dict(ledger_sha256=s.sha(cfg['budget_ledger_path']),events=len(s.load(cfg['budget_ledger_path'])['events']),
        spent_cny=s.load(cfg['budget_ledger_path'])['spent_cny'],original_plan_sha256=s.sha(live/'study_plan.json'),
        original_package_sha256=s.sha(live/'验收包.zip'),template_sha256=s.sha(cfg['codesys_template']),
        fb_sha256=hashlib.sha256(fb.encode()).hexdigest(),program_sha256=hashlib.sha256(program.encode()).hexdigest(),
        worker_sha256=s.sha(WORKER),controller_sha256=s.sha(__file__),platform_identity=identity))
    for name,code,expected in (
        ('reference',fb,dict(testComplete='TRUE',testPassed='TRUE',firstFailedStep='-1',step='13')),
        ('wrong-count-control',fb.replace('elementCount := count;','elementCount := 0;'),dict(testComplete='TRUE',testPassed='FALSE',firstFailedStep='1',step='13'))):
        folder=ROOT/name;folder.mkdir();(folder/'cache').mkdir()
        assert name!='wrong-count-control' or code!=fb
        (folder/'FB.st').write_bytes(code.encode());(folder/'PLC_PRG.st').write_bytes(program.encode())
        job=dict(template=str(Path(cfg['codesys_template']).resolve()),project=str(folder/'validation.project'),
            result=str(folder/'result.json'),nonce=uuid4().hex,simulation_only=True,
            fb=split_st(code),program=split_st(program),expected=expected)
        s.atomic_json(folder/'job.json',job)
        args='"'+cfg['codesys_executable']+'" --noUI --culture=en --profile="'+cfg['codesys_profile']+'" --runscript="'+str(WORKER)+'" --scriptargs:"'+str(folder/'job.json')+'"'
        backend.timeout=120
        print('RUNNING',name,flush=True)
        rc,out,err=backend.run(args,folder)
        (folder/'stdout.log').write_bytes(out.encode());(folder/'stderr.log').write_bytes(err.encode())
        result=s.load(folder/'result.json');assert result and result['nonce']==job['nonce']
        s.atomic_json(folder/'process.json',dict(returncode=rc))
        print(json.dumps(dict(case=name,returncode=rc,status=result['status'],phase=result['phase'],
            final_values=result.get('final_values'),error=result.get('error')),ensure_ascii=False),flush=True)
        assert Path(cfg['budget_ledger_path']).read_bytes()==ledger_before
        if rc!=0 or result['status']!='passed' or result['cleanup_errors']:
            raise RuntimeError('Simulation validation requires review; preserve the stopped case')
    s.atomic_json(ROOT/'completion.json',dict(verified=True,reference_simulation_passed=True,wrong_count_control_rejected=True,
        simulation_only=True,physical_plc_used=False,model_calls=0,completed_at=s.stamp()))
    print('PASS supplied two-instance calling program and negative simulation control',flush=True)

if __name__=='__main__':main()

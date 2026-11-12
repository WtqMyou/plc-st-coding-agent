"""Read-only-to-hardware validation on a fresh local CODESYS simulator project."""
from pathlib import Path
import sys
from uuid import uuid4
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import f14_v5_core as s
from stbench.platforms import split_st
ROOT=Path('E:/PLC_Dev/evidence/incoming_reviews/f14_v5_string_probe_20261112_v2')
FB='''FUNCTION_BLOCK FB
VAR_OUTPUT firstByte:INT;dotByte:INT;endByte:INT;END_VAR
VAR txt:STRING(8):='1.';END_VAR
firstByte:=BYTE_TO_INT(txt[0]);dotByte:=BYTE_TO_INT(txt[1]);endByte:=BYTE_TO_INT(txt[2]);
END_FUNCTION_BLOCK'''
PROGRAM='''PROGRAM PLC_PRG
VAR probe:FB;step:INT;testComplete:BOOL;testPassed:BOOL:=TRUE;firstFailedStep:INT:=-1;END_VAR
IF NOT testComplete THEN
probe();
IF probe.firstByte<>49 OR probe.dotByte<>46 OR probe.endByte<>0 THEN testPassed:=FALSE;firstFailedStep:=0;END_IF;
step:=1;testComplete:=TRUE;
END_IF;
END_PROGRAM'''


def main():
    cfg=s.config();assert not ROOT.exists(),'Retain prior probe evidence'
    ROOT.mkdir(parents=True);(ROOT/'cache').mkdir()
    ledger=Path(cfg['budget_ledger_path']);before=ledger.read_bytes()
    job=dict(template=cfg['codesys_template'],project=str(ROOT/'probe.project'),result=str(ROOT/'result.json'),nonce=uuid4().hex,
        simulation_only=True,fb=split_st(FB),program=split_st(PROGRAM),
        watch_names=['testComplete','testPassed','firstFailedStep','step','probe.firstByte','probe.dotByte','probe.endByte'],
        expected=dict(testComplete='TRUE',testPassed='TRUE',firstFailedStep='-1',step='1',**{'probe.firstByte':'49','probe.dotByte':'46','probe.endByte':'0'}))
    s.atomic_json(ROOT/'job.json',job)
    (ROOT/'FB.st').write_text(FB,encoding='utf-8');(ROOT/'PLC_PRG.st').write_text(PROGRAM,encoding='utf-8')
    worker=s.REPO/'progress/f14_agent_v2/codesys_probe_worker.py'
    args='"'+cfg['codesys_executable']+'" --noUI --culture=en --profile="'+cfg['codesys_profile']+'" --runscript="'+str(worker)+'" --scriptargs:"'+str(ROOT/'job.json')+'"'
    backend=s.old.old.support.CodesysBackend(dict(cfg,platform_root=str(ROOT)));backend.timeout=120
    rc,out,err=backend.run(args,ROOT)
    (ROOT/'stdout.log').write_text(out,encoding='utf-8');(ROOT/'stderr.log').write_text(err,encoding='utf-8')
    result=s.load(ROOT/'result.json')
    assert rc==0 and result['status']=='passed' and result['native_execution'] and not result['cleanup_errors'],result
    assert ledger.read_bytes()==before
    s.atomic_json(ROOT/'completion.json',dict(passed=True,model_requests=0,ledger_sha256=s.sha(ledger),
        worker_sha256=s.sha(worker),controller_sha256=s.sha(__file__),result_sha256=s.sha(ROOT/'result.json')))
    print('PASS actual CODESYS simulation: digit byte 49, dot byte 46, terminator byte 0; no API call',flush=True)


if __name__=='__main__':main()

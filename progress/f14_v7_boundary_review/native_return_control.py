"""Verify the original generated reset/RETURN code on the real local CODESYS simulator."""
from pathlib import Path
import sys
from uuid import uuid4
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import f14_v6_core as s
from stbench.platforms import split_st
ROOT=Path('E:/PLC_Dev/evidence/incoming_reviews/f14_v7_return_native_20261112_v2')
PROGRAM='''PROGRAM PLC_PRG
VAR probe:FB;step:INT;testComplete:BOOL;testPassed:BOOL:=TRUE;firstFailedStep:INT:=-1;tmp_expected:LREAL;END_VAR
IF NOT testComplete THEN
CASE step OF
0:probe(cyclicExecution:=TRUE,trigger:=FALSE,value:=LREAL#7.0,windowSize:=2,reset:=TRUE);tmp_expected:=0.0;
1:probe(cyclicExecution:=TRUE,trigger:=FALSE,value:=LREAL#9.0,windowSize:=2,reset:=FALSE);tmp_expected:=9.0;
2:probe(cyclicExecution:=TRUE,trigger:=FALSE,value:=LREAL#13.0,windowSize:=2,reset:=TRUE);tmp_expected:=0.0;
3:probe(cyclicExecution:=TRUE,trigger:=FALSE,value:=LREAL#5.0,windowSize:=2,reset:=FALSE);tmp_expected:=5.0;
END_CASE;
IF (probe.average<>tmp_expected) OR probe.windowSizeReached OR probe.error OR (probe.status<>WORD#0) THEN
 IF testPassed THEN firstFailedStep:=step;END_IF;
 testPassed:=FALSE;
END_IF;
IF step=3 THEN testComplete:=TRUE;ELSE step:=step+1;END_IF;
END_IF;
END_PROGRAM'''


def main():
    cfg=s.config();assert not ROOT.exists(),'Retain native control evidence'
    ledger=Path(cfg['budget_ledger_path']);before=ledger.read_bytes();ROOT.mkdir(parents=True)
    source=Path(__file__).with_name('developer_candidates')/'public-medium-03.original.st'
    code=source.read_text(encoding='utf-8');worker=Path(__file__).with_name('codesys_control_worker.py');rows=[]
    for label,fb,expected_status in [('original_return',code,'passed'),('removed_return_negative',code.replace('RETURN;','average := average; (* RETURN disabled only in this negative control *)'),'test_failed')]:
        folder=ROOT/label;folder.mkdir();(folder/'cache').mkdir()
        job=dict(template=cfg['codesys_template'],project=str(folder/'control.project'),result=str(folder/'result.json'),nonce=uuid4().hex,
            simulation_only=True,fb=split_st(fb),program=split_st(PROGRAM),
            watch_names=['testComplete','testPassed','firstFailedStep','step','probe.average','probe.windowSizeReached','probe.error','probe.status'],
            expected=dict(testComplete='TRUE',testPassed='TRUE',firstFailedStep='-1',step='3'))
        s.atomic_json(folder/'job.json',job)
        (folder/'FB.st').write_bytes(fb.encode());(folder/'PLC_PRG.st').write_text(PROGRAM,encoding='utf-8')
        args='"'+cfg['codesys_executable']+'" --noUI --culture=en --profile="'+cfg['codesys_profile']+'" --runscript="'+str(worker)+'" --scriptargs:"'+str(folder/'job.json')+'"'
        backend=s.old.old.support.CodesysBackend(dict(cfg,platform_root=str(folder)));backend.timeout=120
        rc,out,err=backend.run(args,folder)
        (folder/'stdout.log').write_text(out,encoding='utf-8');(folder/'stderr.log').write_text(err,encoding='utf-8')
        result=s.load(folder/'result.json')
        assert result['status']==expected_status and result['native_execution'] and not result['cleanup_errors'],result
        rows.append(dict(label=label,status=expected_status,source_sha256=s.sha(folder/'FB.st'),result_sha256=s.sha(folder/'result.json')))
    assert ledger.read_bytes()==before
    s.atomic_json(ROOT/'completion.json',dict(passed=True,model_calls=0,ledger_unchanged=True,ledger_sha256=s.sha(ledger),
        original_candidate_sha256=s.sha(source),rows=rows,worker_sha256=s.sha(worker),controller_sha256=s.sha(__file__)))
    print('PASS real CODESYS: original reset/RETURN answer passes; deliberately removed RETURN fails; no model calls',flush=True)


if __name__=='__main__':main()

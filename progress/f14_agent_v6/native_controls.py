"""Actual local simulation controls for compound value assignment and numeric/string semantics."""
from pathlib import Path
import sys
from uuid import uuid4
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import f14_v6_core as s
from stbench.platforms import split_st
ROOT=Path('E:/PLC_Dev/evidence/incoming_reviews/f14_v6_native_controls_20261112')
DUT='TYPE ST_V6_Copy : STRUCT ident:INT; items:ARRAY[0..1] OF INT; END_STRUCT END_TYPE'
FB='''FUNCTION_BLOCK FB
VAR_OUTPUT copyPassed:BOOL;arrayPassed:BOOL;realPassed:BOOL;stringPassed:BOOL;END_VAR
VAR originalRecord,copiedRecord:ST_V6_Copy;originalArray,copiedArray:ARRAY[0..1] OF INT;
txt:STRING(8):='1.'; narrowReal:REAL;wideReal:LREAL;END_VAR
originalRecord.ident:=7;originalRecord.items[0]:=11;copiedRecord:=originalRecord;
copiedRecord.ident:=0;copiedRecord.items[0]:=0;
copyPassed:=(originalRecord.ident=7) AND (originalRecord.items[0]=11);
originalArray[0]:=3;copiedArray:=originalArray;copiedArray[0]:=0;
arrayPassed:=(originalArray[0]=3);
narrowReal:=TO_REAL(DINT#16777217);wideReal:=TO_LREAL(DINT#16777217);
realPassed:=(narrowReal=REAL#16777216.0) AND (wideReal=LREAL#16777217.0);
stringPassed:=(BYTE_TO_INT(txt[0])=49) AND (BYTE_TO_INT(txt[1])=46) AND (BYTE_TO_INT(txt[2])=0);
END_FUNCTION_BLOCK'''
PROGRAM='''PROGRAM PLC_PRG
VAR probe:FB;step:INT;testComplete:BOOL;testPassed:BOOL:=TRUE;firstFailedStep:INT:=-1;END_VAR
IF NOT testComplete THEN
probe();
IF NOT probe.copyPassed OR NOT probe.arrayPassed OR NOT probe.realPassed OR NOT probe.stringPassed THEN
 testPassed:=FALSE;firstFailedStep:=0;
END_IF;
step:=1;testComplete:=TRUE;
END_IF;
END_PROGRAM'''


def main():
    cfg=s.config();assert not ROOT.exists(),'Keep existing control evidence'
    ledger=Path(cfg['budget_ledger_path']);before=ledger.read_bytes();ROOT.mkdir(parents=True)
    worker=Path(__file__).with_name('codesys_control_worker.py');results=[]
    for label,source,status in [('positive',FB,'passed'),('negative',FB.replace('copiedRecord.ident:=0','originalRecord.ident:=0'),'test_failed')]:
        folder=ROOT/label;folder.mkdir();(folder/'cache').mkdir()
        job=dict(template=cfg['codesys_template'],project=str(folder/'control.project'),result=str(folder/'result.json'),nonce=uuid4().hex,
            simulation_only=True,fb=split_st(source),program=split_st(PROGRAM),duts=[dict(name='ST_V6_Copy',declaration=DUT)],
            watch_names=['testComplete','testPassed','firstFailedStep','step','probe.copyPassed','probe.arrayPassed','probe.realPassed','probe.stringPassed'],
            expected=dict(testComplete='TRUE',testPassed='TRUE',firstFailedStep='-1',step='1',
                **{'probe.copyPassed':'TRUE','probe.arrayPassed':'TRUE','probe.realPassed':'TRUE','probe.stringPassed':'TRUE'}))
        s.atomic_json(folder/'job.json',job)
        (folder/'FB.st').write_text(DUT+'\n'+source,encoding='utf-8');(folder/'PLC_PRG.st').write_text(PROGRAM,encoding='utf-8')
        args='"'+cfg['codesys_executable']+'" --noUI --culture=en --profile="'+cfg['codesys_profile']+'" --runscript="'+str(worker)+'" --scriptargs:"'+str(folder/'job.json')+'"'
        backend=s.old.old.support.CodesysBackend(dict(cfg,platform_root=str(folder)));backend.timeout=120
        rc,out,err=backend.run(args,folder)
        (folder/'stdout.log').write_text(out,encoding='utf-8');(folder/'stderr.log').write_text(err,encoding='utf-8')
        result=s.load(folder/'result.json')
        assert result['status']==status and result['native_execution'] and not result['cleanup_errors'],result
        results.append(dict(label=label,status=status,result_sha256=s.sha(folder/'result.json')))
    assert ledger.read_bytes()==before
    s.atomic_json(ROOT/'completion.json',dict(passed=True,model_calls=0,ledger_unchanged=True,ledger_sha256=s.sha(ledger),results=results,
        worker_sha256=s.sha(worker),controller_sha256=s.sha(__file__)))
    print('PASS actual CODESYS positive and deliberately incorrect negative controls; zero API calls',flush=True)


if __name__=='__main__':main()

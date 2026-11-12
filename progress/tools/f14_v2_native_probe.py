"""Free local CODESYS simulation validates edge FBs and DWORD bit access."""
from pathlib import Path
import sys
from uuid import uuid4
sys.path.insert(0,str(Path(__file__).resolve().parent))
import f14_no80 as n
from stbench.platforms import split_st
ROOT=Path('E:/PLC_Dev/evidence/incoming_reviews/f14_v2_native_probe_20261112_v3')
FB='''FUNCTION_BLOCK FB
VAR_INPUT signal:BOOL; END_VAR
VAR_OUTPUT rQ:BOOL; fQ:BOOL; bits:DWORD; bitHigh:BOOL; END_VAR
VAR riseDetector:R_TRIG; fallDetector:F_TRIG; x:DWORD; END_VAR
riseDetector(CLK:=signal,Q=>rQ); fallDetector(CLK:=signal,Q=>fQ);
x:=DWORD#16#80000001; bitHigh:=x.31 AND x.0;
x.0:=FALSE; x.30:=TRUE; bits:=x;
END_FUNCTION_BLOCK'''
PROGRAM='''PROGRAM PLC_PRG
VAR probe:FB; step:INT; testComplete:BOOL; testPassed:BOOL:=TRUE;
firstFailedStep:INT:=-1; signal:BOOL; risingCode:DWORD; fallingCode:DWORD; END_VAR
IF NOT testComplete THEN
 signal := (step=1 OR step=2 OR step=5);
 probe(signal:=signal);
 IF probe.rQ THEN risingCode:=risingCode OR SHL(DWORD#1,step); END_IF;
 IF probe.fQ THEN fallingCode:=fallingCode OR SHL(DWORD#1,step); END_IF;
 IF NOT probe.bitHigh OR probe.bits<>DWORD#16#C0000000 THEN testPassed:=FALSE; firstFailedStep:=step; END_IF;
 IF step=6 THEN
  testComplete:=TRUE;
  IF risingCode<>DWORD#34 OR fallingCode<>DWORD#72 THEN testPassed:=FALSE; firstFailedStep:=step; END_IF;
 ELSE step:=step+1; END_IF;
END_IF;
END_PROGRAM'''
def main():
 cfg=n.b.config();assert not ROOT.exists();ROOT.mkdir(parents=True);(ROOT/'cache').mkdir()
 before=Path(cfg['budget_ledger_path']).read_bytes()
 job=dict(template=cfg['codesys_template'],project=str(ROOT/'probe.project'),result=str(ROOT/'result.json'),nonce=uuid4().hex,
  simulation_only=True,fb=split_st(FB),program=split_st(PROGRAM),
  watch_names=['testComplete','testPassed','firstFailedStep','step','risingCode','fallingCode','probe.bits'],
  expected=dict(testComplete='TRUE',testPassed='TRUE',firstFailedStep='-1',step='6',risingCode='34',fallingCode='72'))
 n.atomic_json(ROOT/'job.json',job);(ROOT/'FB.st').write_text(FB,encoding='utf-8');(ROOT/'PLC_PRG.st').write_text(PROGRAM,encoding='utf-8')
 worker=n.REPO/'progress/f14_agent_v2/codesys_probe_worker.py'
 args='"'+cfg['codesys_executable']+'" --noUI --culture=en --profile="'+cfg['codesys_profile']+'" --runscript="'+str(worker)+'" --scriptargs:"'+str(ROOT/'job.json')+'"'
 backend=n.b.base.old.old.support.CodesysBackend(dict(cfg,platform_root=str(ROOT)));backend.timeout=120
 rc,out,err=backend.run(args,ROOT);(ROOT/'stdout.log').write_text(out,encoding='utf-8');(ROOT/'stderr.log').write_text(err,encoding='utf-8')
 result=n.load(ROOT/'result.json');assert rc==0 and result['status']=='passed' and result['native_execution'] and not result['cleanup_errors'],result
 assert Path(cfg['budget_ledger_path']).read_bytes()==before
 n.atomic_json(ROOT/'completion.json',dict(passed=True,model_requests=0,ledger_sha256=n.sha(cfg['budget_ledger_path']),worker_sha256=n.sha(worker),controller_sha256=n.sha(__file__),result_sha256=n.sha(ROOT/'result.json')))
 print('PASS native simulator: R_TRIG 34, F_TRIG 72, DWORD bit read/write; no model calls')
if __name__=='__main__':main()

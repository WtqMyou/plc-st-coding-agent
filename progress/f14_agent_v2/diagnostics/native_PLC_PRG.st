PROGRAM PLC_PRG
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
END_PROGRAM
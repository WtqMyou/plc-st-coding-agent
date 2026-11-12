PROGRAM PLC_PRG
VAR probe:FB;step:INT;testComplete:BOOL;testPassed:BOOL:=TRUE;firstFailedStep:INT:=-1;END_VAR
IF NOT testComplete THEN
probe();
IF probe.firstByte<>49 OR probe.dotByte<>46 OR probe.endByte<>0 THEN testPassed:=FALSE;firstFailedStep:=0;END_IF;
step:=1;testComplete:=TRUE;
END_IF;
END_PROGRAM
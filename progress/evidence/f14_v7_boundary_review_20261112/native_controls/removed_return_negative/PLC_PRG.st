PROGRAM PLC_PRG
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
END_PROGRAM
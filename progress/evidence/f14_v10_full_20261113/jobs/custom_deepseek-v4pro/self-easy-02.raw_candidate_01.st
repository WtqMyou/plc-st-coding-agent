(* ENGINEERING_CONTRACT
   alarmHigh: set when tankLevel >= 85.0; latch until rising resetBtn while high danger absent.
   alarmLow:  set when tankLevel <= 15.0; latch until rising resetBtn while low danger absent.
   Danger has same-scan priority over reset.
   reset edge = resetBtn AND NOT prevResetBtn; prevResetBtn initial FALSE.
   pumpRun = inletPermit AND NOT alarmHigh AND NOT alarmLow after alarm update.
   outletValveOpen = NOT alarmLow.
   outletFlow is unused in this function block.
   All outputs sampled at end of the same scan.
*)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FB
VAR_INPUT
    tankLevel : REAL;
    outletFlow : REAL;
    inletPermit : BOOL;
    resetBtn : BOOL;
END_VAR
VAR_OUTPUT
    pumpRun : BOOL;
    alarmHigh : BOOL;
    alarmLow : BOOL;
    outletValveOpen : BOOL;
END_VAR
VAR
    prevResetBtn : BOOL := FALSE;
    prevAlarmHigh : BOOL := FALSE;
    prevAlarmLow : BOOL := FALSE;
    tmp_highDanger : BOOL;
    tmp_lowDanger : BOOL;
    tmp_resetEdge : BOOL;
    tmp_newHigh : BOOL;
    tmp_newLow : BOOL;
END_VAR

tmp_highDanger := tankLevel >= 85.0;
tmp_lowDanger := tankLevel <= 15.0;
tmp_resetEdge := resetBtn AND NOT prevResetBtn;

IF tmp_highDanger THEN
    tmp_newHigh := TRUE;
ELSIF tmp_resetEdge THEN
    tmp_newHigh := FALSE;
ELSE
    tmp_newHigh := prevAlarmHigh;
END_IF;

IF tmp_lowDanger THEN
    tmp_newLow := TRUE;
ELSIF tmp_resetEdge THEN
    tmp_newLow := FALSE;
ELSE
    tmp_newLow := prevAlarmLow;
END_IF;

alarmHigh := tmp_newHigh;
alarmLow := tmp_newLow;

pumpRun := inletPermit AND NOT alarmHigh AND NOT alarmLow;
outletValveOpen := NOT alarmLow;

prevResetBtn := resetBtn;
prevAlarmHigh := alarmHigh;
prevAlarmLow := alarmLow;

END_FUNCTION_BLOCK
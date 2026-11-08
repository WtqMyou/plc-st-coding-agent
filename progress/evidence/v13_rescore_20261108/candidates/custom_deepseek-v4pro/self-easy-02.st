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
    resetBtnPrev : BOOL;
    resetRising : BOOL;
    alarmHighState : BOOL;
    alarmLowState : BOOL;
END_VAR

resetRising := resetBtn AND NOT resetBtnPrev;

IF tankLevel >= 85.0 THEN
    alarmHighState := TRUE;
ELSIF resetRising THEN
    alarmHighState := FALSE;
END_IF

IF tankLevel <= 15.0 THEN
    alarmLowState := TRUE;
ELSIF resetRising THEN
    alarmLowState := FALSE;
END_IF

pumpRun := (tankLevel >= 15.0 AND tankLevel < 85.0) AND inletPermit AND NOT alarmHighState AND NOT alarmLowState;
outletValveOpen := (tankLevel >= 15.0 AND tankLevel < 85.0) AND inletPermit AND NOT alarmHighState AND NOT alarmLowState;

alarmHigh := alarmHighState;
alarmLow := alarmLowState;

resetBtnPrev := resetBtn;

END_FUNCTION_BLOCK
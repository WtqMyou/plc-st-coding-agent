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
    resetBtnPrev : BOOL := FALSE;
    resetRising : BOOL;
    highLatched : BOOL := FALSE;
    lowLatched : BOOL := FALSE;
END_VAR

resetRising := resetBtn AND NOT resetBtnPrev;

IF tankLevel >= 85.0 THEN
    highLatched := TRUE;
END_IF

IF tankLevel <= 15.0 THEN
    lowLatched := TRUE;
END_IF

IF resetRising THEN
    IF tankLevel < 85.0 THEN
        highLatched := FALSE;
    END_IF
    IF tankLevel > 15.0 THEN
        lowLatched := FALSE;
    END_IF
END_IF

alarmHigh := highLatched;
alarmLow := lowLatched;

IF inletPermit AND NOT highLatched AND tankLevel >= 15.0 AND tankLevel < 85.0 THEN
    pumpRun := TRUE;
ELSE
    pumpRun := FALSE;
END_IF

IF NOT lowLatched AND tankLevel > 15.0 THEN
    outletValveOpen := TRUE;
ELSE
    outletValveOpen := FALSE;
END_IF

resetBtnPrev := resetBtn;

END_FUNCTION_BLOCK
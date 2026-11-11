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
    resetRising : BOOL;
END_VAR

resetRising := resetBtn AND NOT prevResetBtn;

IF tankLevel >= 85.0 THEN
    alarmHigh := TRUE;
END_IF;

IF tankLevel <= 15.0 THEN
    alarmLow := TRUE;
END_IF;

IF resetRising THEN
    IF NOT (tankLevel >= 85.0) THEN
        alarmHigh := FALSE;
    END_IF;
    IF NOT (tankLevel <= 15.0) THEN
        alarmLow := FALSE;
    END_IF;
END_IF;

prevResetBtn := resetBtn;

pumpRun := inletPermit AND NOT alarmHigh AND NOT alarmLow;
outletValveOpen := NOT alarmLow;

END_FUNCTION_BLOCK
FUNCTION_BLOCK FB
VAR_INPUT
    tankLevel    : REAL;
    outletFlow   : REAL;
    inletPermit  : BOOL;
    resetBtn     : BOOL;
END_VAR
VAR_OUTPUT
    pumpRun        : BOOL;
    alarmHigh      : BOOL;
    alarmLow       : BOOL;
    outletValveOpen: BOOL;
END_VAR
VAR
    prevResetBtn   : BOOL := FALSE;
    risingReset    : BOOL;
    alarmHighHold  : BOOL := FALSE;
    alarmLowHold   : BOOL := FALSE;
END_VAR

risingReset := resetBtn AND NOT prevResetBtn;
prevResetBtn := resetBtn;

IF tankLevel >= 85.0 THEN
    alarmHighHold := TRUE;
END_IF

IF tankLevel <= 15.0 THEN
    alarmLowHold := TRUE;
END_IF;

alarmHigh := alarmHighHold;
alarmLow  := alarmLowHold;

IF risingReset THEN
    IF tankLevel < 85.0 AND NOT (tankLevel >= 85.0) THEN
        alarmHighHold := FALSE;
    END_IF
    IF tankLevel > 15.0 AND NOT (tankLevel <= 15.0) THEN
        alarmLowHold := FALSE;
    END_IF
END_IF

pumpRun := inletPermit
    AND (tankLevel < 85.0)
    AND (tankLevel > 15.0)
    AND NOT alarmHighHold;

outletValveOpen := inletPermit
    AND (tankLevel < 85.0)
    AND (tankLevel > 15.0)
    AND NOT alarmHighHold;

alarmHigh := alarmHighHold;
alarmLow  := alarmLowHold;
END_FUNCTION_BLOCK
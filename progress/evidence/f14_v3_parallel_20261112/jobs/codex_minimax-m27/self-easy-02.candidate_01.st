FUNCTION_BLOCK FB
VAR_INPUT
    tankLevel   : REAL;
    outletFlow  : REAL;
    inletPermit : BOOL;
    resetBtn    : BOOL;
END_VAR
VAR_OUTPUT
    pumpRun        : BOOL;
    alarmHigh      : BOOL;
    alarmLow       : BOOL;
    outletValveOpen: BOOL;
END_VAR
VAR
    prevResetBtn : BOOL := FALSE;
    prevAlarmHigh: BOOL := FALSE;
    prevAlarmLow : BOOL := FALSE;
END_VAR
VAR
    resetRising : BOOL;
END_VAR

resetRising := resetBtn AND NOT prevResetBtn;

IF tankLevel >= 85.0 THEN
    alarmHigh := TRUE;
ELSIF resetRising AND NOT (tankLevel >= 85.0) THEN
    alarmHigh := FALSE;
ELSE
    alarmHigh := prevAlarmHigh;
END_IF;

IF tankLevel <= 15.0 THEN
    alarmLow := TRUE;
ELSIF resetRising AND NOT (tankLevel <= 15.0) THEN
    alarmLow := FALSE;
ELSE
    alarmLow := prevAlarmLow;
END_IF;

pumpRun := (NOT alarmHigh) AND (NOT alarmLow) AND inletPermit;

outletValveOpen := NOT alarmLow;

prevResetBtn  := resetBtn;
prevAlarmHigh := alarmHigh;
prevAlarmLow  := alarmLow;
END_FUNCTION_BLOCK
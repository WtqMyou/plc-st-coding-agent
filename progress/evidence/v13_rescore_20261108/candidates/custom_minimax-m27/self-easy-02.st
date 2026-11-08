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
    lastResetBtn : BOOL := FALSE;
    internalAlarmHigh : BOOL := FALSE;
    internalAlarmLow : BOOL := FALSE;
    risingReset : BOOL;
END_VAR

risingReset := resetBtn AND NOT lastResetBtn;
lastResetBtn := resetBtn;

IF tankLevel >= 85.0 THEN
    internalAlarmHigh := TRUE;
ELSIF internalAlarmHigh AND risingReset AND (tankLevel < 85.0) THEN
    internalAlarmHigh := FALSE;
END_IF

IF tankLevel <= 15.0 THEN
    internalAlarmLow := TRUE;
ELSIF internalAlarmLow AND risingReset AND (tankLevel > 15.0) THEN
    internalAlarmLow := FALSE;
END_IF

IF internalAlarmHigh THEN
    pumpRun := FALSE;
ELSIF inletPermit AND (tankLevel < 85.0) AND (tankLevel >= 15.0) THEN
    pumpRun := TRUE;
ELSE
    pumpRun := FALSE;
END_IF

IF internalAlarmLow THEN
    outletValveOpen := FALSE;
ELSIF pumpRun THEN
    outletValveOpen := TRUE;
ELSE
    outletValveOpen := FALSE;
END_IF

alarmHigh := internalAlarmHigh;
alarmLow := internalAlarmLow;

END_FUNCTION_BLOCK
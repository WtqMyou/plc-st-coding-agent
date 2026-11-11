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
    risingReset : BOOL;
END_VAR

risingReset := resetBtn AND NOT prevResetBtn;

alarmHigh := alarmHigh OR (tankLevel >= 85.0);
IF risingReset AND tankLevel < 85.0 THEN
    alarmHigh := FALSE;
END_IF

alarmLow := alarmLow OR (tankLevel <= 15.0);
IF risingReset AND tankLevel > 15.0 THEN
    alarmLow := FALSE;
END_IF

pumpRun := inletPermit AND NOT alarmHigh AND NOT alarmLow;

outletValveOpen := NOT alarmLow;

prevResetBtn := resetBtn;
END_FUNCTION_BLOCK
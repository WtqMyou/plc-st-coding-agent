FUNCTION_BLOCK FB
VAR_INPUT
    tankLevel       : REAL;
    outletFlow      : REAL;
    inletPermit     : BOOL;
    resetBtn        : BOOL;
END_VAR
VAR_OUTPUT
    pumpRun         : BOOL;
    alarmHigh       : BOOL;
    alarmLow        : BOOL;
    outletValveOpen : BOOL;
END_VAR
VAR
    prevResetBtn    : BOOL := FALSE;
    prevAlarmHigh   : BOOL := FALSE;
    prevAlarmLow    : BOOL := FALSE;
    risingReset     : BOOL;
END_VAR

risingReset := resetBtn AND NOT prevResetBtn;

alarmHigh := (tankLevel >= 85.0) OR (prevAlarmHigh AND NOT risingReset);
alarmLow  := (tankLevel <= 15.0) OR (prevAlarmLow  AND NOT risingReset);

pumpRun := inletPermit AND NOT alarmHigh AND NOT alarmLow;

outletValveOpen := NOT alarmLow;

prevResetBtn  := resetBtn;
prevAlarmHigh := alarmHigh;
prevAlarmLow  := alarmLow;
END_FUNCTION_BLOCK
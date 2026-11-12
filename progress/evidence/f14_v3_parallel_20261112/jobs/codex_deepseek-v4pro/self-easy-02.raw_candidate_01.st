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
    highLatched : BOOL := FALSE;
    lowLatched : BOOL := FALSE;
    prevReset : BOOL := FALSE;
    resetRising : BOOL;
    oldHigh : BOOL;
    oldLow : BOOL;
END_VAR

resetRising := resetBtn AND NOT prevReset;

oldHigh := highLatched;
oldLow := lowLatched;

highLatched := (tankLevel >= 85.0) OR (oldHigh AND NOT resetRising);
lowLatched := (tankLevel <= 15.0) OR (oldLow AND NOT resetRising);

alarmHigh := highLatched;
alarmLow := lowLatched;

pumpRun := inletPermit AND NOT alarmHigh AND NOT alarmLow;
outletValveOpen := NOT alarmLow;

prevReset := resetBtn;
END_FUNCTION_BLOCK
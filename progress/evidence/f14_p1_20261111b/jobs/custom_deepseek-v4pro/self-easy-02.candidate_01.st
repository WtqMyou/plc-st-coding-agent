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
    resetEdge : BOOL;
    highDanger : BOOL;
    lowDanger : BOOL;
    highAlarm : BOOL;
    lowAlarm : BOOL;
    pumpCmd : BOOL;
    valveOpen : BOOL;
END_VAR

resetEdge := resetBtn AND NOT prevResetBtn;

highDanger := tankLevel >= 85.0;
lowDanger := tankLevel <= 15.0;

IF highDanger THEN
    highAlarm := TRUE;
ELSE
    highAlarm := prevAlarmHigh AND NOT resetEdge;
END_IF;

IF lowDanger THEN
    lowAlarm := TRUE;
ELSE
    lowAlarm := prevAlarmLow AND NOT resetEdge;
END_IF;

pumpCmd := inletPermit AND NOT highAlarm AND NOT lowAlarm;
valveOpen := NOT lowAlarm;

alarmHigh := highAlarm;
alarmLow := lowAlarm;
pumpRun := pumpCmd;
outletValveOpen := valveOpen;

prevAlarmHigh := highAlarm;
prevAlarmLow := lowAlarm;
prevResetBtn := resetBtn;

END_FUNCTION_BLOCK
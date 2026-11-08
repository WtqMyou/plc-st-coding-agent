FUNCTION_BLOCK FB
VAR_INPUT
    startBtn : BOOL;
    resetBtn : BOOL;
    doneSensor : BOOL;
    targetVol : REAL;
    flowVol : REAL;
END_VAR
VAR_OUTPUT
    valveOpen : BOOL;
    fillsToday : INT;
END_VAR
VAR
    startR : BOOL;
    resetR : BOOL;
    lastStart : BOOL;
    lastReset : BOOL;
    accumulated : REAL;
    stage : INT;
END_VAR

startR := startBtn AND NOT lastStart;
resetR := resetBtn AND NOT lastReset;

IF resetR THEN
    stage := 0;
    valveOpen := FALSE;
    fillsToday := 0;
    accumulated := 0.0;
ELSIF startR AND stage = 0 THEN
    stage := 1;
    valveOpen := TRUE;
    accumulated := 0.0;
END_IF;

IF stage = 1 THEN
    accumulated := accumulated + flowVol;
    IF accumulated >= targetVol THEN
        valveOpen := FALSE;
        stage := 2;
    END_IF;
END_IF;

IF stage = 2 AND doneSensor THEN
    fillsToday := fillsToday + 1;
    stage := 0;
END_IF;

lastStart := startBtn;
lastReset := resetBtn;

END_FUNCTION_BLOCK
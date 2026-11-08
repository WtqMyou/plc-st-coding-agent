FUNCTION_BLOCK FB
VAR_INPUT
    startBtn   : BOOL;
    resetBtn   : BOOL;
    doneSensor : BOOL;
    targetVol  : REAL;
    flowVol    : REAL;
END_VAR

VAR_OUTPUT
    valveOpen  : BOOL;
    fillsToday : INT := 0;
END_VAR

VAR
    prevStartBtn : BOOL := FALSE;
    prevResetBtn : BOOL := FALSE;
    currentVol   : REAL := 0.0;
    filling      : BOOL := FALSE;
END_VAR

VAR_TEMP
    startRising : BOOL;
    resetRising : BOOL;
END_VAR

startRising := startBtn AND NOT prevStartBtn;
resetRising := resetBtn AND NOT prevResetBtn;

prevStartBtn := startBtn;
prevResetBtn := resetBtn;

IF resetRising THEN
    fillsToday := 0;
    valveOpen  := FALSE;
    currentVol := 0.0;
    filling    := FALSE;
    RETURN;
END_IF

IF startRising AND NOT filling AND NOT valveOpen THEN
    valveOpen  := TRUE;
    currentVol := 0.0;
    filling    := TRUE;
END_IF

IF valveOpen THEN
    currentVol := currentVol + flowVol;
    IF currentVol >= targetVol THEN
        valveOpen := FALSE;
    END_IF;
END_IF;

IF filling AND (NOT valveOpen) AND doneSensor THEN
    fillsToday := fillsToday + 1;
    filling    := FALSE;
END_IF;

END_FUNCTION_BLOCK
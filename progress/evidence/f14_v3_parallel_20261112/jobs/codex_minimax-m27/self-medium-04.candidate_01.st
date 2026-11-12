FUNCTION_BLOCK FB
VAR_INPUT
    startBtn    : BOOL;
    resetBtn    : BOOL;
    doneSensor  : BOOL;
    targetVol   : REAL;
    flowVol     : REAL;
END_VAR
VAR_OUTPUT
    valveOpen   : BOOL := FALSE;
    fillsToday  : INT := 0;
END_VAR
VAR
    prevStartBtn   : BOOL := FALSE;
    prevResetBtn   : BOOL := FALSE;
    prevValveOpen  : BOOL := FALSE;
    prevFillsToday : INT := 0;
    pending        : BOOL := FALSE;
    accumVol       : REAL := 0.0;
END_VAR

VAR
    risingStartBtn : BOOL;
    risingResetBtn : BOOL;
END_VAR

risingStartBtn := startBtn AND NOT prevStartBtn;
risingResetBtn := resetBtn AND NOT prevResetBtn;

prevFillsToday := fillsToday;
prevValveOpen  := valveOpen;

IF risingResetBtn THEN
    fillsToday := 0;
    pending    := FALSE;
    valveOpen  := FALSE;
    accumVol   := 0.0;
    prevFillsToday := 0;
    prevValveOpen  := FALSE;
ELSIF risingStartBtn THEN
    IF pending THEN
        pending := FALSE;
    END_IF;
    valveOpen := TRUE;
    accumVol  := 0.0;
ELSIF valveOpen THEN
    accumVol := accumVol + flowVol;
    IF accumVol >= targetVol THEN
        valveOpen := FALSE;
        pending   := TRUE;
    END_IF;
END_IF;

IF pending THEN
    IF doneSensor THEN
        IF prevFillsToday < 32767 THEN
            fillsToday := prevFillsToday + 1;
        ELSE
            fillsToday := 32767;
        END_IF;
        pending := FALSE;
    END_IF;
END_IF;

prevStartBtn  := startBtn;
prevResetBtn  := resetBtn;
END_FUNCTION_BLOCK
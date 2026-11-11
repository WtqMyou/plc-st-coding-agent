FUNCTION_BLOCK FB
VAR_INPUT
    startBtn    : BOOL;
    resetBtn    : BOOL;
    doneSensor  : BOOL;
    targetVol   : REAL;
    flowVol     : REAL;
END_VAR
VAR_OUTPUT
    valveOpen   : BOOL;
    fillsToday  : INT := 0;
END_VAR
VAR
    prevStartBtn   : BOOL := FALSE;
    prevResetBtn   : BOOL := FALSE;
    prevValveOpen  : BOOL := FALSE;
    accumulatedVol : REAL := 0.0;
    state          : INT := 0;
    startRising    : BOOL;
    resetRising    : BOOL;
    valveFalling   : BOOL;
END_VAR

    startRising  := startBtn AND NOT prevStartBtn;
    resetRising  := resetBtn AND NOT prevResetBtn;
    valveFalling := prevValveOpen AND NOT valveOpen;

    IF resetRising THEN
        fillsToday      := 0;
        accumulatedVol  := 0.0;
        valveOpen       := FALSE;
        state           := 0;
    ELSIF state = 0 THEN
        IF startRising THEN
            accumulatedVol := flowVol;
            state          := 1;
        END_IF;
    ELSIF state = 1 THEN
        accumulatedVol := accumulatedVol + flowVol;
        IF accumulatedVol >= targetVol THEN
            state := 2;
        END_IF;
    ELSIF state = 2 THEN
        IF doneSensor AND (fillsToday < 32767) THEN
            fillsToday := fillsToday + 1;
            state      := 0;
        END_IF;
    END_IF;

    valveOpen := (state = 1);

    prevStartBtn   := startBtn;
    prevResetBtn   := resetBtn;
    prevValveOpen  := valveOpen;
END_FUNCTION_BLOCK
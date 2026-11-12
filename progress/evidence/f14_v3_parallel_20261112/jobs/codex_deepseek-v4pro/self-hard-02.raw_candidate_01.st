FUNCTION_BLOCK FB
VAR_INPUT
    startBtn    : BOOL;
    abortBtn    : BOOL;
    setpoint    : REAL;
    pv          : REAL;
    maxDuration : INT;
END_VAR
VAR_OUTPUT
    elapsed : INT;
    phase   : INT;
    timeout : BOOL;
END_VAR
VAR
    prevStart    : BOOL;
    statePhase   : INT;
    stateElapsed : INT;
    stateTimeout : BOOL;
END_VAR

IF abortBtn THEN
    statePhase := 9;
ELSIF startBtn AND NOT prevStart THEN
    statePhase   := 1;
    stateElapsed := 0;
    stateTimeout := FALSE;
ELSE
    IF statePhase = 1 OR statePhase = 2 THEN
        stateElapsed := stateElapsed + 1;
        IF stateElapsed >= maxDuration THEN
            stateTimeout := TRUE;
            statePhase   := 3;
        ELSIF statePhase = 2 THEN
            stateTimeout := FALSE;
            statePhase   := 2;
        ELSIF pv >= setpoint THEN
            stateTimeout := FALSE;
            statePhase   := 2;
        ELSE
            stateTimeout := FALSE;
            statePhase   := 1;
        END_IF;
    END_IF;
END_IF;

phase   := statePhase;
elapsed := stateElapsed;
timeout := stateTimeout;

prevStart := startBtn;

END_FUNCTION_BLOCK
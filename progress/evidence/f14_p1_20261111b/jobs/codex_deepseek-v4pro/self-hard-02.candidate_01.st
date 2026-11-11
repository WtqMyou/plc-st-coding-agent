FUNCTION_BLOCK FB
VAR_INPUT
    startBtn : BOOL;
    abortBtn : BOOL;
    setpoint : REAL;
    pv : REAL;
    maxDuration : INT;
END_VAR
VAR_OUTPUT
    elapsed : INT;
    phase : INT;
    timeout : BOOL;
END_VAR
VAR
    lastStartBtn : BOOL;
    startRising : BOOL;
    prevPhase : INT;
    prevElapsed : INT;
    prevTimeout : BOOL;
END_VAR

startRising := startBtn AND NOT lastStartBtn;
prevPhase := phase;
prevElapsed := elapsed;
prevTimeout := timeout;

IF abortBtn THEN
    phase := 9;
    elapsed := prevElapsed;
    timeout := prevTimeout;
ELSIF startRising THEN
    phase := 1;
    elapsed := 0;
    timeout := FALSE;
ELSIF (prevPhase = 1) OR (prevPhase = 2) THEN
    elapsed := prevElapsed + 1;

    IF maxDuration <= elapsed THEN
        timeout := TRUE;
        phase := 3;
    ELSE
        timeout := FALSE;

        IF (prevPhase = 2) OR (pv >= setpoint) THEN
            phase := 2;
        ELSE
            phase := 1;
        END_IF;
    END_IF;
ELSE
    phase := prevPhase;
    elapsed := prevElapsed;
    timeout := prevTimeout;
END_IF;

lastStartBtn := startBtn;
END_FUNCTION_BLOCK
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
    prevStartBtn : BOOL := FALSE;
    prevPhase : INT := 0;
    prevElapsed : INT := 0;
    prevTimeout : BOOL := FALSE;
    startRising : BOOL;
    currentPhase : INT := 0;
    currentElapsed : INT := 0;
    currentTimeout : BOOL := FALSE;
END_VAR

startRising := startBtn AND NOT prevStartBtn;

IF abortBtn THEN
    currentPhase := 9;
    currentElapsed := prevElapsed;
    currentTimeout := prevTimeout;
ELSIF startRising THEN
    currentPhase := 1;
    currentElapsed := 0;
    currentTimeout := FALSE;
ELSIF (prevPhase = 1) OR (prevPhase = 2) THEN
    currentElapsed := prevElapsed + 1;
    IF maxDuration <= currentElapsed THEN
        currentTimeout := TRUE;
        currentPhase := 3;
    ELSE
        currentTimeout := FALSE;
        IF (prevPhase = 2) OR (pv >= setpoint) THEN
            currentPhase := 2;
        ELSE
            currentPhase := 1;
        END_IF;
    END_IF;
ELSE
    currentPhase := prevPhase;
    currentElapsed := prevElapsed;
    currentTimeout := prevTimeout;
END_IF;

prevStartBtn := startBtn;
prevPhase := currentPhase;
prevElapsed := currentElapsed;
prevTimeout := currentTimeout;

phase := currentPhase;
elapsed := currentElapsed;
timeout := currentTimeout;
END_FUNCTION_BLOCK
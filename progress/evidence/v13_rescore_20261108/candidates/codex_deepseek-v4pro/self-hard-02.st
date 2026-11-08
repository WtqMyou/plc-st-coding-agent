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
    startRising : BOOL;
    lastStart : BOOL;
END_VAR

startRising := startBtn AND NOT lastStart;

IF startRising THEN
    elapsed := 0;
    phase := 1;
    timeout := FALSE;
ELSIF abortBtn THEN
    phase := 9;
ELSIF (phase = 1) OR (phase = 2) THEN
    elapsed := elapsed + 1;

    IF elapsed >= maxDuration THEN
        timeout := TRUE;
        phase := 3;
    ELSIF (phase = 1) AND (pv >= setpoint) THEN
        phase := 2;
    END_IF;
END_IF;

lastStart := startBtn;
END_FUNCTION_BLOCK
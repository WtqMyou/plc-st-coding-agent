FUNCTION_BLOCK FB
VAR_INPUT
    startBtn    : BOOL;
    abortBtn    : BOOL;
    setpoint    : REAL;
    pv          : REAL;
    maxDuration : INT;
END_VAR
VAR_OUTPUT
    elapsed  : INT := 0;
    phase    : INT := 0;
    timeout  : BOOL := FALSE;
END_VAR
VAR
    prevStartBtn : BOOL := FALSE;
    prevAbortBtn : BOOL := FALSE;
    startRising  : BOOL := FALSE;
END_VAR

startRising := startBtn AND NOT prevStartBtn;

prevStartBtn := startBtn;
prevAbortBtn := abortBtn;

IF abortBtn THEN
    phase := 9;
    timeout := FALSE;
    elapsed := 0;
    RETURN;
END_IF

IF startRising THEN
    phase := 1;
    elapsed := 0;
    timeout := FALSE;
    RETURN;
END_IF

IF phase = 0 THEN
    RETURN;
END_IF

IF phase = 1 THEN
    elapsed := elapsed + 1;
    IF pv >= setpoint THEN
        phase := 2;
    END_IF
END_IF

IF phase = 2 THEN
    elapsed := elapsed + 1;
    IF elapsed >= maxDuration THEN
        timeout := TRUE;
        phase := 3;
    END_IF
END_IF

IF phase = 9 THEN
    RETURN;
END_IF;

END_FUNCTION_BLOCK
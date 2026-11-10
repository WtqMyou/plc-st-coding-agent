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
    startEdgeInputPrev : BOOL;
    startEdge : BOOL;
END_VAR
startEdge := startBtn AND NOT startEdgeInputPrev;
startEdgeInputPrev := startBtn;
IF abortBtn THEN
    phase := 9;
ELSIF startEdge THEN
    phase := 1;
    elapsed := 0;
    timeout := FALSE;
ELSIF phase = 1 OR phase = 2 THEN
    elapsed := elapsed + 1;
    IF elapsed >= maxDuration THEN
        timeout := TRUE;
        phase := 3;
    ELSIF phase = 1 AND pv >= setpoint THEN
        phase := 2;
    END_IF
END_IF
END_FUNCTION_BLOCK

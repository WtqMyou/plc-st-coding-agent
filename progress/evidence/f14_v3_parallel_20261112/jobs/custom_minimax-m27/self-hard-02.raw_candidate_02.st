FUNCTION_BLOCK FB
VAR_INPUT
    startBtn   : BOOL;
    abortBtn   : BOOL;
    setpoint   : REAL;
    pv         : REAL;
    maxDuration: INT;
END_VAR
VAR_OUTPUT
    elapsed  : INT  := 0;
    phase    : INT  := 0;
    timeout  : BOOL := FALSE;
END_VAR
VAR
    prev_startBtn : BOOL := FALSE;
    prev_phase    : INT  := 0;
    risingEdge    : BOOL;
END_VAR

    risingEdge := startBtn AND NOT prev_startBtn;

    IF abortBtn THEN
        phase := 9;
        elapsed := elapsed;
        timeout := timeout;

    ELSIF risingEdge THEN
        elapsed := 0;
        timeout := FALSE;
        phase   := 1;

    ELSIF (prev_phase = 1) OR (prev_phase = 2) THEN
        elapsed := elapsed + 1;

        IF elapsed >= maxDuration THEN
            timeout := TRUE;
            phase   := 3;
        ELSE
            IF (prev_phase = 2) OR (pv >= setpoint) THEN
                phase := 2;
            ELSE
                phase := 1;
            END_IF;
        END_IF;

    ELSE
        NULL;
    END_IF;

    prev_startBtn := startBtn;
    prev_phase    := phase;
END_FUNCTION_BLOCK
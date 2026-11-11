FUNCTION_BLOCK FB
VAR_INPUT
    startBtn    : BOOL;
    abortBtn    : BOOL;
    setpoint    : REAL;
    pv          : REAL;
    maxDuration : INT;
END_VAR
VAR_OUTPUT
    elapsed  : INT;
    phase    : INT;
    timeout  : BOOL;
END_VAR
VAR
    prev_startBtn : BOOL := FALSE;
    prev_phase    : INT  := 0;
END_VAR

prev_startBtn := startBtn;
prev_phase    := phase;

IF abortBtn THEN
    phase := 9;
ELSIF startBtn AND NOT prev_startBtn THEN
    phase   := 1;
    elapsed := 0;
    timeout := FALSE;
ELSE
    IF prev_phase = 1 OR prev_phase = 2 THEN
        elapsed := elapsed + 1;
        IF elapsed >= maxDuration THEN
            timeout := TRUE;
            phase   := 3;
        ELSIF pv >= setpoint THEN
            phase := 2;
        ELSE
            phase := 1;
        END_IF;
    END_IF;
END_IF;
END_FUNCTION_BLOCK
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
    prev_start : BOOL := FALSE;
    prev_phase : INT := 0;
    prev_elapsed : INT := 0;
    prev_timeout : BOOL := FALSE;
    start_rising : BOOL;
END_VAR

start_rising := startBtn AND NOT prev_start;

IF abortBtn THEN
    phase := 9;
    elapsed := prev_elapsed;
    timeout := prev_timeout;
    prev_start := startBtn;
    prev_phase := phase;
    prev_elapsed := elapsed;
    prev_timeout := timeout;
ELSIF start_rising THEN
    phase := 1;
    elapsed := 0;
    timeout := FALSE;
    prev_start := startBtn;
    prev_phase := phase;
    prev_elapsed := elapsed;
    prev_timeout := timeout;
ELSE
    IF (prev_phase = 1) OR (prev_phase = 2) THEN
        elapsed := prev_elapsed + 1;
        IF maxDuration <= elapsed THEN
            timeout := TRUE;
            phase := 3;
        ELSE
            timeout := FALSE;
            IF (prev_phase = 2) OR (pv >= setpoint) THEN
                phase := 2;
            ELSE
                phase := 1;
            END_IF;
        END_IF;
    ELSE
        phase := prev_phase;
        elapsed := prev_elapsed;
        timeout := prev_timeout;
    END_IF;
    prev_start := startBtn;
    prev_phase := phase;
    prev_elapsed := elapsed;
    prev_timeout := timeout;
END_IF;
END_FUNCTION_BLOCK
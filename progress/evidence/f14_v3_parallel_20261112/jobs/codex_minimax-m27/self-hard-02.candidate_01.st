FUNCTION_BLOCK FB
VAR_INPUT
    startBtn    : BOOL;
    abortBtn    : BOOL;
    setpoint    : REAL;
    pv          : REAL;
    maxDuration : INT;
END_VAR
VAR_OUTPUT
    elapsed : INT := 0;
    phase   : INT := 0;
    timeout : BOOL := FALSE;
END_VAR
VAR
    prev_startBtn : BOOL := FALSE;
    prev_phase    : INT  := 0;
    prev_elapsed  : INT  := 0;
    prev_timeout  : BOOL := FALSE;
END_VAR

// Priority 1: Abort (highest)
IF abortBtn THEN
    phase   := 9;
    elapsed := prev_elapsed;
    timeout := prev_timeout;

// Priority 2: New start rising edge (no abort)
ELSIF startBtn AND NOT prev_startBtn THEN
    phase   := 1;
    elapsed := 0;
    timeout := FALSE;

// Priority 3: Running states (prev phase 1 or 2)
ELSIF prev_phase = 1 OR prev_phase = 2 THEN
    elapsed := prev_elapsed + 1;
    
    IF elapsed >= maxDuration THEN
        timeout := TRUE;
        phase   := 3;
    ELSIF prev_phase = 1 AND pv >= setpoint THEN
        phase := 2;
    ELSE
        phase := prev_phase;
    END_IF;

// Priority 4: Frozen states (phase 0, 3, 9)
ELSE
    phase   := prev_phase;
    elapsed := prev_elapsed;
    timeout := prev_timeout;
END_IF;

prev_startBtn := startBtn;
prev_phase    := phase;
prev_elapsed  := elapsed;
prev_timeout  := timeout;
END_FUNCTION_BLOCK
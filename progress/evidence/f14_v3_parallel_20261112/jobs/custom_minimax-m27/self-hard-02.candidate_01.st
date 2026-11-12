FUNCTION_BLOCK FB
VAR_INPUT
    startBtn   : BOOL;
    abortBtn   : BOOL;
    setpoint   : REAL;
    pv         : REAL;
    maxDuration: INT;
END_VAR
VAR_OUTPUT
    elapsed : INT := 0;
    phase   : INT := 0;
    timeout : BOOL := FALSE;
END_VAR
VAR
    prev_startBtn : BOOL := FALSE;
    prev_phase    : INT  := 0;
    risingEdge    : BOOL;
END_VAR

    // Detect rising edge of startBtn before any state changes this scan
    risingEdge := startBtn AND NOT prev_startBtn;

    // Priority 1: abort
    IF abortBtn THEN
        phase   := 9;
        // elapsed and timeout stay frozen (no assignment)

    // Priority 2: new rising edge (only if not aborted this scan)
    ELSIF risingEdge THEN
        elapsed := 0;
        timeout := FALSE;
        phase   := 1;

    // Priority 3: running phases — count and evaluate transition
    ELSIF (prev_phase = 1) OR (prev_phase = 2) THEN
        elapsed := elapsed + 1;

        // Check timeout before setting phase
        IF elapsed >= maxDuration THEN
            timeout := TRUE;
            phase   := 3;
        ELSE
            // Phase transition based on temperature
            IF (prev_phase = 2) OR (pv >= setpoint) THEN
                phase := 2;
            ELSE
                phase := 1;
            END_IF;
        END_IF;

    // Frozen states (phase 0, 3, 9) — no changes to elapsed/phase/timeout
    ELSE
        // phase, elapsed, timeout retain their values
    END_IF;

    // Update previous-cycle snapshot for next scan
    prev_startBtn := startBtn;
    prev_phase    := phase;
END_FUNCTION_BLOCK
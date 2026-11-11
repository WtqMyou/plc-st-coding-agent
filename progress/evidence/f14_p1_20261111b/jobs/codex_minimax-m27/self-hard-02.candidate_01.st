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

; Save previous values at start of each scan cycle
prev_startBtn := startBtn;
prev_phase    := phase;

; Priority: abort > new start edge > running count
; Highest priority: abortBtn immediately transitions to phase=9
IF abortBtn THEN
    phase := 9;
    ; elapsed and timeout remain unchanged from previous scan
    
; No abort: check for new start rising edge
ELSIF startBtn AND NOT prev_startBtn THEN
    phase    := 1;
    elapsed  := 0;
    timeout  := FALSE;
    
; Normal operation: no abort, no new start edge
ELSE
    ; Running phases (1 or 2) accumulate scan counts
    IF prev_phase = 1 OR prev_phase = 2 THEN
        elapsed := elapsed + 1;
        
        ; Check timeout condition (takes priority over pv-based transition)
        IF elapsed >= maxDuration THEN
            timeout := TRUE;
            phase   := 3;
        ; pv-based phase transition when not timed out
        ELSIF pv >= setpoint THEN
            phase := 2;
        ELSE
            phase := 1;
        END_IF;
    END_IF;
    
    ; Frozen states (phase=3 or phase=9) keep their values
    ; No action needed - phase, elapsed, timeout retain previous values
END_IF;
END_FUNCTION_BLOCK
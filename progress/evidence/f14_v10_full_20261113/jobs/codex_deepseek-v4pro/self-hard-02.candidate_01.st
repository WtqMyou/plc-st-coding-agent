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
    local_rt : R_TRIG;
    local_rising : BOOL;
    local_prev_phase : INT;
    local_prev_elapsed : INT;
    local_prev_timeout : BOOL;
    local_counted_elapsed : INT;
END_VAR
(* ENGINEERING_CONTRACT
   phase: no-abort start edge -> 1; counted elapsed >= maxDuration -> 3; abort -> 9; otherwise hold 0/1/2/3/9.
   elapsed: +1 only when previous phase 1 or 2, no abort and no start edge; otherwise kept at previous value.
   timeout: set with phase 3 when counted elapsed >= maxDuration; cleared on a no-abort start edge; otherwise held.
   priority: abort > rising start edge > run counting, including same scan start edge.
   start scan does not count. Units: elapsed/maxDuration are scan counts, INT; phase INT 0/1/2/3/9.
   Unspecified: abort plus same-scan start edge keeps phase 9 and consumes that start edge.
*)
(* CONTRACT_RULES [] *)
local_rt(CLK := startBtn);
local_rising := local_rt.Q;

local_prev_phase := phase;
local_prev_elapsed := elapsed;
local_prev_timeout := timeout;

IF abortBtn THEN
    phase := 9;
    elapsed := local_prev_elapsed;
    timeout := local_prev_timeout;
ELSIF local_rising THEN
    phase := 1;
    elapsed := 0;
    timeout := FALSE;
ELSIF (local_prev_phase = 1) OR (local_prev_phase = 2) THEN
    local_counted_elapsed := local_prev_elapsed + 1;
    elapsed := local_counted_elapsed;

    IF local_counted_elapsed >= maxDuration THEN
        timeout := TRUE;
        phase := 3;
    ELSE
        timeout := FALSE;
        IF (local_prev_phase = 2) OR (pv >= setpoint) THEN
            phase := 2;
        ELSE
            phase := 1;
        END_IF;
    END_IF;
ELSE
    phase := local_prev_phase;
    elapsed := local_prev_elapsed;
    timeout := local_prev_timeout;
END_IF;
END_FUNCTION_BLOCK
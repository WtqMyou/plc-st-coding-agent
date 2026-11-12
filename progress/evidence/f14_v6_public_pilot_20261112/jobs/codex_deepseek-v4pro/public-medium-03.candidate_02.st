(* ENGINEERING_CONTRACT
average: updates on each accepted sample (PUB002/PUB003), holds between samples; reset=TRUE clears it in the same scan; units LREAL.
windowSizeReached: TRUE when stored sample count >= windowSize; reset=TRUE clears it; invalid window clears it; recomputed every valid scan.
error/status: error=TRUE and status=16#8200 only when windowSize<1 or >100; otherwise FALSE/16#0000 (PUB004, PUB006, PUB007).
capture_priority: reset=TRUE suppresses capture; cyclicExecution=TRUE captures every scan and trigger has no effect; trigger uses one rising edge when cyclicExecution=FALSE.
window_resize: if a valid windowSize is smaller than stored count, oldest samples are discarded to the new width before capture; this detail is unspecified by PUB and implemented consistently.
boundaries: windowSize 1..100, circular buffer capacity 100 LREAL; divisor INT_TO_LREAL(local_count); windowSizeReached includes the equal boundary.
*)
(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FB
VAR_INPUT
    cyclicExecution : BOOL;
    trigger : BOOL;
    value : LREAL;
    windowSize : INT;
    reset : BOOL;
END_VAR
VAR_OUTPUT
    average : LREAL;
    windowSizeReached : BOOL;
    error : BOOL;
    status : WORD;
END_VAR
VAR
    local_buffer : ARRAY[0..99] OF LREAL;
    local_count : INT := 0;
    local_head : INT := 0;
    local_sum : LREAL := 0.0;
    local_trigger_rt : R_TRIG;
    local_append_index : INT;
END_VAR

local_trigger_rt(CLK := trigger);

IF reset THEN
    local_count := 0;
    local_head := 0;
    local_sum := 0.0;
    average := 0.0;
    windowSizeReached := FALSE;
END_IF;

IF (windowSize < 1) OR (windowSize > 100) THEN
    error := TRUE;
    status := 16#8200;
    windowSizeReached := FALSE;
ELSE
    error := FALSE;
    status := 16#0000;

    WHILE local_count > windowSize DO
        local_sum := local_sum - local_buffer[local_head];
        local_head := (local_head + 1) MOD 100;
        local_count := local_count - 1;
    END_WHILE;

    IF local_count > 0 THEN
        average := local_sum / INT_TO_LREAL(local_count);
    ELSE
        average := 0.0;
    END_IF;

    windowSizeReached := local_count >= windowSize;

    IF NOT reset THEN
        IF cyclicExecution OR local_trigger_rt.Q THEN
            IF local_count < windowSize THEN
                local_append_index := (local_head + local_count) MOD 100;
                local_buffer[local_append_index] := value;
                local_sum := local_sum + value;
                local_count := local_count + 1;
            ELSE
                local_sum := local_sum - local_buffer[local_head] + value;
                local_buffer[local_head] := value;
                local_head := (local_head + 1) MOD 100;
            END_IF;

            IF local_count > 0 THEN
                average := local_sum / INT_TO_LREAL(local_count);
            END_IF;

            windowSizeReached := local_count >= windowSize;
        END_IF;
    END_IF;
END_IF;

END_FUNCTION_BLOCK
(* ENGINEERING_CONTRACT
average: activates when a sample is accepted or the valid window changes; holds the last valid result otherwise; reset sets it to 0.0.
windowSizeReached: TRUE while retained sample count >= windowSize; reset or invalid window forces FALSE.
error/status: windowSize < 1 or windowSize > 100 sets error=TRUE and status=16#8200; a valid window sets error=FALSE and status=16#0000.
capture priority: cyclicExecution=TRUE captures every scan and suppresses trigger; trigger uses R_TRIG only while cyclicExecution=FALSE; reset suppresses capture.
window resize: shrinking removes the oldest points so only the most recent windowSize values remain; growing preserves retained points and continues filling without resetting.
reset: level-triggered on reset=TRUE; clears head, count, sum, average, and windowSizeReached.
invalid window preserves retained data but prevents new samples and forces windowSizeReached=FALSE.
Boundaries: windowSize is 1..100; storage is ARRAY[0..99] OF LREAL; average divides by INT_TO_LREAL(count).
PUB001, PUB002, PUB003, PUB004, PUB006, PUB007.
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
    local_count : INT;
    local_head : INT;
    local_sum : LREAL;
    local_to_remove : INT;
    local_insert_index : INT;
    local_trigger_rt : R_TRIG;
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

    IF local_count > windowSize THEN
        local_to_remove := local_count - windowSize;
        WHILE local_to_remove > 0 DO
            local_sum := local_sum - local_buffer[local_head];
            local_head := local_head + 1;
            IF local_head >= 100 THEN
                local_head := 0;
            END_IF;
            local_to_remove := local_to_remove - 1;
        END_WHILE;
        local_count := windowSize;
    END_IF;

    IF NOT reset THEN
        IF cyclicExecution OR (local_trigger_rt.Q AND (NOT cyclicExecution)) THEN
            IF local_count < windowSize THEN
                local_insert_index := (local_head + local_count) MOD 100;
                local_buffer[local_insert_index] := value;
                local_sum := local_sum + value;
                local_count := local_count + 1;
            ELSE
                local_sum := local_sum - local_buffer[local_head] + value;
                local_buffer[local_head] := value;
                local_head := local_head + 1;
                IF local_head >= 100 THEN
                    local_head := 0;
                END_IF;
            END_IF;
        END_IF;
    END_IF;

    IF local_count > 0 THEN
        average := local_sum / INT_TO_LREAL(local_count);
    END_IF;

    windowSizeReached := local_count >= windowSize;
END_IF;

END_FUNCTION_BLOCK
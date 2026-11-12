(* ENGINEERING_CONTRACT
average: activated when a sample is accepted; otherwise holds last valid result; reset sets it to 0.0; units are inherited from value (LREAL).
windowSizeReached: TRUE when accepted sample count >= windowSize; holds until reset or invalid window; no edge-only behavior.
error/status: windowSize < 1 or windowSize > 100 sets error=TRUE and status=16#8200; valid window sets error=FALSE and status=16#0000.
capture priority: cyclicExecution=TRUE captures every scan and suppresses trigger; trigger uses R_TRIG only while cyclicExecution=FALSE; reset suppresses capture.
reset: level-triggered on reset=TRUE, clears sum, buffer count, write index, average, and windowSizeReached.
invalid window preserves accumulated average data but forces windowSizeReached=FALSE and prevents new samples.
Boundaries: windowSize is 1..100; storage is ARRAY[0..99] OF LREAL; average division uses INT_TO_LREAL.
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
    local_write_index : INT;
    local_sum : LREAL;
    local_trigger_rt : R_TRIG;
END_VAR

local_trigger_rt(CLK := trigger);

IF reset THEN
    local_count := 0;
    local_write_index := 0;
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

    IF NOT reset THEN
        IF cyclicExecution OR (local_trigger_rt.Q AND (NOT cyclicExecution)) THEN
            IF local_count < windowSize THEN
                local_buffer[local_count] := value;
                local_sum := local_sum + value;
                local_count := local_count + 1;
            ELSE
                local_sum := local_sum - local_buffer[local_write_index] + value;
                local_buffer[local_write_index] := value;
                local_write_index := local_write_index + 1;
                IF local_write_index >= windowSize THEN
                    local_write_index := 0;
                END_IF;
            END_IF;

            IF local_count > 0 THEN
                average := local_sum / INT_TO_LREAL(local_count);
            END_IF;

            windowSizeReached := local_count >= windowSize;
        END_IF;
    END_IF;
END_IF;

END_FUNCTION_BLOCK
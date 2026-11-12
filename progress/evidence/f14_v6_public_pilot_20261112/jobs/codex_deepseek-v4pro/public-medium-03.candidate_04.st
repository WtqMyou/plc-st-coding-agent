(* ENGINEERING_CONTRACT
average: updated on each accepted sample; otherwise holds last valid result; reset sets it to 0.0; units/value domain follow input value (LREAL).
windowSizeReached: TRUE while retained sample count >= current valid windowSize; reset clears it; invalid window forces FALSE.
error/status: windowSize 1..100 -> FALSE/16#0000; otherwise -> TRUE/16#8200. Reset is evaluated before window validation.
capture priority: cyclicExecution=TRUE captures every scan and ignores trigger; otherwise R_TRIG trigger captures; reset suppresses capture in the same scan.
resize: a valid windowSize reduction shrinks retained history to the latest windowSize samples and recomputes average before capture.
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
    local_sum : LREAL;
    local_trigger_rt : R_TRIG;
    tmp_i : INT;
    tmp_old : LREAL;
END_VAR

local_trigger_rt(CLK := trigger);

IF reset THEN
    local_count := 0;
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
        local_sum := local_sum - local_buffer[0];
        IF local_count > 1 THEN
            FOR tmp_i := 0 TO local_count - 2 DO
                local_buffer[tmp_i] := local_buffer[tmp_i + 1];
            END_FOR;
        END_IF;
        local_count := local_count - 1;
    END_WHILE;

    IF local_count > 0 THEN
        average := local_sum / INT_TO_LREAL(local_count);
    END_IF;

    windowSizeReached := local_count >= windowSize;

    IF NOT reset THEN
        IF cyclicExecution OR local_trigger_rt.Q THEN
            IF local_count < windowSize THEN
                local_buffer[local_count] := value;
                local_sum := local_sum + value;
                local_count := local_count + 1;
            ELSE
                tmp_old := local_buffer[0];
                IF local_count > 1 THEN
                    FOR tmp_i := 0 TO local_count - 2 DO
                        local_buffer[tmp_i] := local_buffer[tmp_i + 1];
                    END_FOR;
                END_IF;
                local_buffer[local_count - 1] := value;
                local_sum := local_sum - tmp_old + value;
            END_IF;

            IF local_count > 0 THEN
                average := local_sum / INT_TO_LREAL(local_count);
            END_IF;

            windowSizeReached := local_count >= windowSize;
        END_IF;
    END_IF;
END_IF;

END_FUNCTION_BLOCK
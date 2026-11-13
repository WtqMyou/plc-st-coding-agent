FUNCTION_BLOCK FB_MovingAverage
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
    local_sampleCount : INT;
    local_nextWrite : INT;
    local_triggerPrevious : BOOL;
    local_windowValid : BOOL;
    local_update : BOOL;
    local_i : INT;
    local_age : INT;
    local_position : INT;
    local_sum : LREAL;
END_VAR

(* CONTRACT_RULES [] *)

(* ENGINEERING_CONTRACT
   average: updated after valid acquisition (PUB001/PUB002); recalculated while window valid; 0.0 on reset; retained on invalid/no-reset.
   windowSizeReached: TRUE when stored sample count >= windowSize; cleared by reset and invalid window (PUB006).
   error/status: combinational from 1..100 window check (PUB003/PUB004); 16#8200 wins over 16#0000.
   reset: level-active; clears history, average, reached; suppresses same-scan acquisition (PUB003).
   acquisition: cyclicExecution first (PUB001); trigger edge only when cyclicExecution is FALSE (PUB002).
   retention: last up to 100 samples retained; mean is over newest windowSize samples (PUB001/PUB006).
   boundaries: valid windowSize 1..100 inclusive; trigger edge consumed every scan to avoid stale queuing.
*)

local_windowValid := (windowSize >= 1) AND (windowSize <= 100);

IF local_windowValid THEN
    error := FALSE;
    status := 16#0000;
ELSE
    error := TRUE;
    status := 16#8200;
END_IF;

IF reset THEN
    local_sampleCount := 0;
    local_nextWrite := 0;
    average := 0.0;
    windowSizeReached := FALSE;

    FOR local_i := 0 TO 99 BY 1 DO
        local_buffer[local_i] := 0.0;
    END_FOR;
ELSE
    IF NOT local_windowValid THEN
        windowSizeReached := FALSE;
    ELSE
        local_update := FALSE;

        IF cyclicExecution THEN
            local_update := TRUE;
        ELSIF (trigger AND NOT local_triggerPrevious) THEN
            local_update := TRUE;
        END_IF;

        IF local_update THEN
            local_buffer[local_nextWrite] := value;
            local_nextWrite := (local_nextWrite + 1) MOD 100;

            IF local_sampleCount < 100 THEN
                local_sampleCount := local_sampleCount + 1;
            END_IF;
        END_IF;

        local_sum := 0.0;

        IF local_sampleCount >= windowSize THEN
            FOR local_i := 0 TO windowSize - 1 BY 1 DO
                local_age := windowSize - 1 - local_i;
                local_position := (local_nextWrite + 100 - 1 - local_age) MOD 100;
                local_sum := local_sum + local_buffer[local_position];
            END_FOR;

            average := local_sum / INT_TO_LREAL(windowSize);
            windowSizeReached := TRUE;
        ELSIF local_sampleCount > 0 THEN
            FOR local_i := 0 TO local_sampleCount - 1 BY 1 DO
                local_age := local_sampleCount - 1 - local_i;
                local_position := (local_nextWrite + 100 - 1 - local_age) MOD 100;
                local_sum := local_sum + local_buffer[local_position];
            END_FOR;

            average := local_sum / INT_TO_LREAL(local_sampleCount);
            windowSizeReached := FALSE;
        ELSE
            average := 0.0;
            windowSizeReached := FALSE;
        END_IF;
    END_IF;
END_IF;

local_triggerPrevious := trigger;

END_FUNCTION_BLOCK
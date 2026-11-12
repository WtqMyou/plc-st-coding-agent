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
    local_triggerEdge : R_TRIG;
    local_samples : ARRAY[0..99] OF LREAL;
    local_sampleCount : INT;
    local_index : INT;
    local_limit : INT;
    local_sum : LREAL;
END_VAR

(*
ENGINEERING_CONTRACT
average: activation = each valid acquisition (cyclicExecution TRUE every scan, or trigger rising edge while cyclicExecution FALSE); retention = holds last computed value until next acquisition; explicit reset = reset TRUE; same-scan priority = reset before acquisition; invalid window also clears calculation state in this implementation; units LREAL.
windowSizeReached: activation = sampleCount >= valid windowSize; retention = remains TRUE once reached; explicit reset = reset TRUE; invalid window clears it.
error/status: error FALSE + status 16#0000 on valid window; error TRUE + status 16#8200 when windowSize < 1 or windowSize > 100; invalid window is checked first.
trigger/cyclic: cyclicExecution TRUE disables trigger; trigger uses rising edge only. PUB001-PUB007.
*)

(* CONTRACT_RULES [] *)

local_triggerEdge(CLK := trigger);

error := FALSE;
status := 16#0000;

IF (windowSize < 1) OR (windowSize > 100) THEN
    error := TRUE;
    status := 16#8200;
    average := 0.0;
    windowSizeReached := FALSE;
    local_sampleCount := 0;
    RETURN;
END_IF;

IF local_sampleCount >= windowSize THEN
    windowSizeReached := TRUE;
ELSE
    windowSizeReached := FALSE;
END_IF;

IF reset THEN
    local_sampleCount := 0;
    average := 0.0;
    windowSizeReached := FALSE;
    RETURN;
END_IF;

IF cyclicExecution OR local_triggerEdge.Q THEN
    IF local_sampleCount < 100 THEN
        local_sampleCount := local_sampleCount + 1;
    END_IF;

    FOR local_index := 99 TO 1 BY -1 DO
        local_samples[local_index] := local_samples[local_index - 1];
    END_FOR;
    local_samples[0] := value;

    local_limit := windowSize;
    IF local_limit > local_sampleCount THEN
        local_limit := local_sampleCount;
    END_IF;

    local_sum := 0.0;
    IF local_limit > 0 THEN
        FOR local_index := 0 TO local_limit - 1 DO
            local_sum := local_sum + local_samples[local_index];
        END_FOR;
        average := local_sum / INT_TO_LREAL(local_limit);
    ELSE
        average := 0.0;
    END_IF;

    IF local_sampleCount >= windowSize THEN
        windowSizeReached := TRUE;
    ELSE
        windowSizeReached := FALSE;
    END_IF;
END_IF;

END_FUNCTION_BLOCK
(* ENGINEERING_CONTRACT
- average: stored LREAL; updated on valid acquisition; reset or invalid window clears it to 0.0.
- windowSizeReached: FALSE until count >= windowSize; retained until reset or invalid window.
- error/status: combinational invalid windowSize (1..100 inclusive); otherwise clear/zero.
- Priority: invalid window first, reset second, acquisition last (reset priority chosen).
- cyclicExecution TRUE ignores trigger edges for extra samples (PUB001/2).
- trigger edge is evaluated only from previous scan raw trigger state.
- Same-scan: validate window, detect window-size change, reset, acquire, update average.
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
    tmp_buffer : ARRAY[0..99] OF LREAL;
    tmp_count : INT := 0;
    tmp_index : INT := 0;
    tmp_sum : LREAL := 0.0;
    tmp_previousTrigger : BOOL := FALSE;
    tmp_windowSize : INT := 0;
END_VAR

IF (windowSize < 1) OR (windowSize > 100) THEN
    error := TRUE;
    status := WORD#16#8200;
    windowSizeReached := FALSE;
    average := 0.0;
    tmp_count := 0;
    tmp_index := 0;
    tmp_sum := 0.0;
    tmp_windowSize := windowSize;
ELSE
    error := FALSE;
    status := WORD#16#0000;

    IF tmp_windowSize <> windowSize THEN
        tmp_count := 0;
        tmp_index := 0;
        tmp_sum := 0.0;
        windowSizeReached := FALSE;
        average := 0.0;
        tmp_windowSize := windowSize;
    END_IF;

    IF reset THEN
        tmp_count := 0;
        tmp_index := 0;
        tmp_sum := 0.0;
        windowSizeReached := FALSE;
        average := 0.0;
    ELSE
        IF cyclicExecution OR (trigger AND NOT tmp_previousTrigger) THEN
            IF tmp_count < windowSize THEN
                tmp_count := tmp_count + 1;
                tmp_sum := tmp_sum + value;
                tmp_buffer[tmp_index] := value;
                tmp_index := tmp_index + 1;
                IF tmp_index >= windowSize THEN
                    tmp_index := 0;
                END_IF;
            ELSE
                tmp_sum := tmp_sum - tmp_buffer[tmp_index] + value;
                tmp_buffer[tmp_index] := value;
                tmp_index := tmp_index + 1;
                IF tmp_index >= windowSize THEN
                    tmp_index := 0;
                END_IF;
            END_IF;

            average := tmp_sum / INT_TO_LREAL(tmp_count);
            windowSizeReached := tmp_count >= windowSize;
        END_IF;
    END_IF;
END_IF;

tmp_previousTrigger := trigger;
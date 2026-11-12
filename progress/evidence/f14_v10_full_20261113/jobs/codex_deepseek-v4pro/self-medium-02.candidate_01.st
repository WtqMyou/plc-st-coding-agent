(* ENGINEERING_CONTRACT
 * Activation: enable TRUE -> push rawValue into 8-slot FIFO, then average all currently valid samples.
 * Retention: filteredValue holds its last computed value while enable is FALSE, including persistent disable.
 * Reset: enable FALSE clears ring buffer, count, and write pointer in the same scan; sampleCount := 0 and windowFull := FALSE.
 * Same-scan priority: disabled branch bypasses sampling; count/full reflect end-of-cycle state, filteredValue is not advanced.
 * Bounds/units: sampleCount is INT 0..8, increments each enabled scan until 8 and then stays 8; windowFull is TRUE iff sampleCount = 8.
 *)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FB
VAR_INPUT
    enable : BOOL;
    rawValue : REAL;
END_VAR
VAR_OUTPUT
    filteredValue : REAL;
    windowFull : BOOL;
    sampleCount : INT;
END_VAR
VAR
    local_buffer : ARRAY[0..7] OF REAL;
    local_count : INT := 0;
    local_write_index : INT := 0;
    local_sum : REAL := 0.0;
    local_filtered : REAL := 0.0;
    local_i : INT;
END_VAR

IF enable THEN
    local_buffer[local_write_index] := rawValue;
    local_write_index := (local_write_index + 1) MOD 8;

    IF local_count < 8 THEN
        local_count := local_count + 1;
    END_IF;

    local_sum := 0.0;

    IF local_count < 8 THEN
        FOR local_i := 0 TO local_count - 1 DO
            local_sum := local_sum + local_buffer[local_i];
        END_FOR;
        local_filtered := local_sum / INT_TO_REAL(local_count);
    ELSE
        FOR local_i := 0 TO 7 DO
            local_sum := local_sum + local_buffer[local_i];
        END_FOR;
        local_filtered := local_sum / 8.0;
    END_IF;

    sampleCount := local_count;
    windowFull := (local_count = 8);
ELSE
    local_count := 0;
    local_write_index := 0;

    FOR local_i := 0 TO 7 DO
        local_buffer[local_i] := 0.0;
    END_FOR;

    sampleCount := 0;
    windowFull := FALSE;
END_IF;

filteredValue := local_filtered;

END_FUNCTION_BLOCK
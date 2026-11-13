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
    tmp_buffer : ARRAY[0..7] OF REAL;
    tmp_count : INT := 0;
    tmp_write_index : INT := 0;
    tmp_sum : REAL := 0.0;
    tmp_i : INT := 0;
END_VAR

(* ENGINEERING_CONTRACT
- filteredValue: recomputed every enabled scan after push; disabled scan retains last mean (PUB005, PUB010).
- sampleCount: 0..8, increments while enabled and <8, holds at 8, resets same scan when disabled (PUB008, PUB010).
- windowFull: TRUE exactly when tmp_count=8; held until disable resets FALSE (PUB009, PUB010).
- FIFO: non-full uses actual count, no zero padding; full replaces oldest (PUB006, PUB007).
- new period: independent count; first enabled sample outputs raw, second outputs two-sample mean (PUB011, S6-S7).
- unspecified: disable ignores rawValue; stored array bits may remain but count defines validity.
*)

IF enable THEN
    IF tmp_count < 8 THEN
        tmp_buffer[tmp_count] := rawValue;
        tmp_count := tmp_count + 1;
        IF tmp_count < 8 THEN
            tmp_write_index := tmp_count;
        ELSE
            tmp_write_index := 0;
        END_IF;
    ELSE
        tmp_buffer[tmp_write_index] := rawValue;
        tmp_write_index := tmp_write_index + 1;
        IF tmp_write_index > 7 THEN
            tmp_write_index := 0;
        END_IF;
    END_IF;

    tmp_sum := 0.0;
    FOR tmp_i := 0 TO tmp_count - 1 DO
        tmp_sum := tmp_sum + tmp_buffer[tmp_i];
    END_FOR;

    IF tmp_count > 0 THEN
        filteredValue := tmp_sum / INT_TO_REAL(tmp_count);
    END_IF;

    sampleCount := tmp_count;
    windowFull := (tmp_count = 8);
ELSE
    tmp_count := 0;
    tmp_write_index := 0;
    sampleCount := 0;
    windowFull := FALSE;
END_IF;

(* CONTRACT_RULES [] *)

END_FUNCTION_BLOCK
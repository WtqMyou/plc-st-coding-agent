(*
ENGINEERING_CONTRACT
- filteredValue: combinational average of actual buffer samples while enable=TRUE; retained unchanged when enable=FALSE (PUB006/S5).
- windowFull: retained full flag; set TRUE when sampleCount reaches 8; held while enabled; reset only by enable=FALSE (PUB005/S2/S3).
- sampleCount: state; increments on each enabled scan up to 8; held at 8 while enabled; reset to 0 same scan on disable (PUB004/S3/S4).
- buffer: 8-slot ring; never zero-filled in average; partial count uses only actual samples PUB001/PUB002/S1; full count FIFO overwrite oldest PUB003.
- Priority: enable=FALSE clears history/window and leaves filteredValue untouched before any sampling.
- Units/boundaries: rawValue/filteredValue REAL sample units; sampleCount INT 0..8; threshold exactly 8.
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
    tmp_buffer : ARRAY[0..7] OF REAL;
    tmp_count : INT := 0;
    tmp_head : INT := 0;
    tmp_i : INT;
    tmp_sum : REAL;
END_VAR

IF enable THEN
    tmp_buffer[tmp_head] := rawValue;
    tmp_head := ((tmp_head + 1) MOD 8);
    IF tmp_count < 8 THEN
        tmp_count := tmp_count + 1;
    END_IF;
    sampleCount := tmp_count;
    windowFull := (tmp_count >= 8);
    tmp_sum := 0.0;
    IF tmp_count > 0 THEN
        FOR tmp_i := 0 TO tmp_count - 1 DO
            tmp_sum := tmp_sum + tmp_buffer[tmp_i];
        END_FOR;
        filteredValue := tmp_sum / INT_TO_REAL(tmp_count);
    END_IF;
ELSE
    tmp_count := 0;
    tmp_head := 0;
    sampleCount := 0;
    windowFull := FALSE;
    FOR tmp_i := 0 TO 7 DO
        tmp_buffer[tmp_i] := 0.0;
    END_FOR;
    (* filteredValue intentionally remains at last computed result *)
END_IF;
END_FUNCTION_BLOCK
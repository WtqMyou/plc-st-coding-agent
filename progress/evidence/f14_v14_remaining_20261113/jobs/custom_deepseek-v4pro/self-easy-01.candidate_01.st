(*
ENGINEERING_CONTRACT
- activation: avgOut updates only when enable=TRUE AND avgEnable=TRUE AND count>0 after clipping count into 1..8.
- hold/retention: enable=FALSE, avgEnable=FALSE, or count<=0 leaves local_avg and avgOut unchanged this scan (S1/S2/S5).
- reset: none specified; avgOut persists until next valid compute; initial local_avg defaults to 0.0.
- boundary: count<=0 causes no division; count>8 uses first 8 samples only (PUB003/PUB004, no overflow).
- precision: sum accumulated in LINT, then converted to REAL and divided by REAL sample count (PUB005/PUB006).
- interface types preserved exactly; no edge-only triggers or interlocks added.
*)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FB
VAR_INPUT
    enable: BOOL;
    values: ARRAY[1..8] OF INT;
    count: INT;
    avgEnable: BOOL;
END_VAR
VAR_OUTPUT
    avgOut: REAL;
END_VAR
VAR
    tmp_len: INT;
    tmp_sum: LINT;
    tmp_i: INT;
    local_avg: REAL := 0.0;
END_VAR

IF enable AND avgEnable THEN
    tmp_len := count;
    IF tmp_len < 0 THEN
        tmp_len := 0;
    END_IF;
    IF tmp_len > 8 THEN
        tmp_len := 8;
    END_IF;
    IF tmp_len > 0 THEN
        tmp_sum := 0;
        FOR tmp_i := 1 TO tmp_len BY 1 DO
            tmp_sum := tmp_sum + INT_TO_LINT(values[tmp_i]);
        END_FOR;
        local_avg := LINT_TO_REAL(tmp_sum) / INT_TO_REAL(tmp_len);
    END_IF;
END_IF;

avgOut := local_avg;

END_FUNCTION_BLOCK
FUNCTION_BLOCK FB
VAR_INPUT
    enable : BOOL;
    values : ARRAY[1..8] OF INT;
    count : INT;
    avgEnable : BOOL;
END_VAR
VAR_OUTPUT
    avgOut : REAL;
END_VAR
VAR
    tmp_i : INT;
    tmp_len : INT;
    tmp_sum : LINT;
END_VAR

(* ENGINEERING_CONTRACT
- Writes avgOut only when enable=TRUE AND avgEnable=TRUE AND count>=1.
- Holds previous avgOut for !enable (PUB003), !avgEnable (PUB007), or count<=0 (PUB005).
- count>8 uses first 8 entries only; no out-of-range access (PUB006).
- Same-scan priority: hold condition is checked first, so no competing write occurs.
- Activation/deactivation: no reset input; output is replaced only by a valid calculation.
- Units/boundaries: avgOut REAL = LINT sum / REAL length; sum uses LINT (PUB008, PUB009).
*)

(* CONTRACT_RULES [] *)

IF enable AND avgEnable AND (count > 0) THEN
    IF count >= 8 THEN
        tmp_len := 8;
    ELSE
        tmp_len := count;
    END_IF;

    tmp_sum := 0;

    FOR tmp_i := 1 TO tmp_len DO
        tmp_sum := tmp_sum + INT_TO_LINT(values[tmp_i]);
    END_FOR;

    avgOut := LINT_TO_REAL(tmp_sum) / INT_TO_REAL(tmp_len);
END_IF;

END_FUNCTION_BLOCK
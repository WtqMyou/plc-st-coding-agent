(*
ENGINEERING_CONTRACT
avgOut REAL output:
- Activation: enable AND avgEnable AND count>=1 -> avgOut = sum(values[1..min(count,8)]) / min(count,8) using DINT accumulation and REAL division.
- Hold/retention: enable=FALSE or avgEnable=FALSE or count<=0 -> avgOut := tmp_heldOut (previous value); no arithmetic or division in same scan.
- Reset/deactivation: no dedicated reset input; held value persists in VAR tmp_heldOut. Initial avgOut/tmp_heldOut = 0.0 (unspecified).
- Same-scan priority: any hold condition suppresses update; count>8 is clipped to 8 before summing.
- Units/bounds: INT samples converted to DINT; sum range max +/-262144; REAL result, no rounding; count negative not used.
*)
(* CONTRACT_RULES [] *)
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
    tmp_sum : DINT;
    tmp_count : INT;
    tmp_i : INT;
    tmp_heldOut : REAL;
END_VAR

IF enable AND avgEnable AND (count >= 1) THEN
    IF count > 8 THEN
        tmp_count := 8;
    ELSE
        tmp_count := count;
    END_IF;

    tmp_sum := 0;
    FOR tmp_i := 1 TO tmp_count BY 1 DO
        tmp_sum := tmp_sum + INT_TO_DINT(values[tmp_i]);
    END_FOR;

    tmp_heldOut := DINT_TO_REAL(tmp_sum) / INT_TO_REAL(tmp_count);
    avgOut := tmp_heldOut;
ELSE
    avgOut := tmp_heldOut;
END_IF;

END_FUNCTION_BLOCK
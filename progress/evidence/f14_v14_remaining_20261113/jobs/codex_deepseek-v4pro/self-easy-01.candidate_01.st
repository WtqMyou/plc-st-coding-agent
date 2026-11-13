FUNCTION_BLOCK FB
(* ENGINEERING_CONTRACT
   avgOut is a retained process value written only on an active valid average scan.
   Activation: enable AND avgEnable AND count >= 1.
   Hold: avgOut remains unchanged when enable=FALSE, avgEnable=FALSE, or count<=0.
   Explicit reset: none specified.
   Same-scan priority: active valid calculation wins; invalid/disabled leaves avgOut unchanged.
   Boundaries: count<1 means no update; count in 1..8 uses count samples; count>8 clips to 8.
   Units: INT samples summed in DINT, divided in REAL; boundary time/scan: current cycle.
   Cite: PUB001-PUB027 behavior clauses; formal S1-S6.
*)
(* CONTRACT_RULES [] *)
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
END_VAR

IF enable AND avgEnable AND (count >= 1) THEN
    tmp_count := count;
    IF tmp_count > 8 THEN
        tmp_count := 8;
    END_IF;

    tmp_sum := 0;
    FOR tmp_i := 1 TO tmp_count DO
        tmp_sum := tmp_sum + INT_TO_DINT(values[tmp_i]);
    END_FOR;

    avgOut := DINT_TO_REAL(tmp_sum) / INT_TO_REAL(tmp_count);
END_IF;

END_FUNCTION_BLOCK
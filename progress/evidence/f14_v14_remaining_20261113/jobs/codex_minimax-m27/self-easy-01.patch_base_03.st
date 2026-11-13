(* ENGINEERING_CONTRACT
================================================================
| Output/State    | Activation           | Retention          | Reset/Deactivation       | Priority | Units          |
|-----------------|----------------------|--------------------|--------------------------|----------|----------------|
| avgOut          | enable AND count>0   | prev value         | enable=FALSE OR count=0  | Same-scan| REAL           |
|                 | AND avgEnable=TRUE   |                    | OR avgEnable=FALSE       |          |                |
================================================================
Behavior:
- avgOut updates only when: enable=TRUE, count>0, avgEnable=TRUE
- avgOut holds (retention) when: enable=FALSE, OR count<=0, OR avgEnable=FALSE
- Sum uses DINT to prevent overflow; division by clipped count (max 8, min 1)
- No NaN possible: division only when count >= 1

*)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FB
VAR
    tmp_sum : DINT := 0;
    tmp_i   : INT  := 0;
END_VAR
VAR_INPUT
    enable     : BOOL;
    values     : ARRAY[1..8] OF INT;
    count      : INT;
    avgEnable  : BOOL;
END_VAR
VAR_OUTPUT
    avgOut : REAL := 0.0;
END_VAR

IF enable AND avgEnable AND count > 0 THEN
    tmp_sum := 0;
    FOR tmp_i := 1 TO MIN(count, 8) DO
        tmp_sum := tmp_sum + INT_TO_DINT(values[tmp_i]);
    END_FOR;
    avgOut := DINT_TO_REAL(tmp_sum) / INT_TO_REAL(MAX(count, 1));
END_IF;
END_FUNCTION_BLOCK
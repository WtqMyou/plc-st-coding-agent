(*
ENGINEERING_CONTRACT
================================================================
Output: avgOut (REAL)
─────────────────────────────────────────────────────────────────
Activation:    Computed every scan when enable AND avgEnable AND count > 0
Retention:     Held when enable=FALSE, avgEnable=FALSE, or count<=0
Reset:         No explicit reset; cold-start avgOut initializes to 0.0
Same-scan:     All inputs evaluated together; final timer state used
Units/bounds:  count: 0..8 clamped to 1..8 for division, sum: DINT
─────────────────────────────────────────────────────────────────
PUB001: enable=TRUE updates avgOut; enable=FALSE retains prev
PUB002: avgEnable input
PUB003: values array[1..8] of INT, 1-indexed sample storage
PUB004: count input INT
PUB005: avgOut output REAL, no rounding to integer
PUB006: count=0 -> no division by zero, avgOut unchanged
PUB007: count>8 -> use only first 8 samples, no out-of-bounds
PUB008: avgEnable=FALSE -> avgOut unchanged (retain)
PUB009: DINT/LINT summation to prevent INT overflow
PUB010: REAL output preserves original precision
================================================================
*)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FB
VAR_INPUT
    enable    : BOOL;
    values    : ARRAY[1..8] OF INT;
    count     : INT;
    avgEnable : BOOL;
END_VAR
VAR_OUTPUT
    avgOut    : REAL := 0.0;
END_VAR
VAR
    tmp_sum   : DINT;
    tmp_count : INT;
END_VAR

tmp_count := count;
IF tmp_count < 1 THEN
    tmp_count := 0;
ELSIF tmp_count > 8 THEN
    tmp_count := 8;
END_IF;

IF enable AND avgEnable AND (tmp_count > 0) THEN
    tmp_sum := 0;
    IF tmp_count >= 1 THEN
        tmp_sum := tmp_sum + TO_DINT(values[1]);
    END_IF;
    IF tmp_count >= 2 THEN
        tmp_sum := tmp_sum + TO_DINT(values[2]);
    END_IF;
    IF tmp_count >= 3 THEN
        tmp_sum := tmp_sum + TO_DINT(values[3]);
    END_IF;
    IF tmp_count >= 4 THEN
        tmp_sum := tmp_sum + TO_DINT(values[4]);
    END_IF;
    IF tmp_count >= 5 THEN
        tmp_sum := tmp_sum + TO_DINT(values[5]);
    END_IF;
    IF tmp_count >= 6 THEN
        tmp_sum := tmp_sum + TO_DINT(values[6]);
    END_IF;
    IF tmp_count >= 7 THEN
        tmp_sum := tmp_sum + TO_DINT(values[7]);
    END_IF;
    IF tmp_count >= 8 THEN
        tmp_sum := tmp_sum + TO_DINT(values[8]);
    END_IF;
    avgOut := TO_REAL(tmp_sum) / TO_REAL(tmp_count);
END_IF;
END_FUNCTION_BLOCK
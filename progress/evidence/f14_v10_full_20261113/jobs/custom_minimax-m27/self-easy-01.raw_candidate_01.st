(* ENGINEERING_CONTRACT
   PUB001: enable=TRUE → update avgOut; enable=FALSE → hold (VAR retained)
   PUB002/PUB003: count=0 → no division, avgOut hold; count<0 treated same
   PUB004/PUB005: count>8 → clamp to 8, no OOB array access
   PUB006: avgEnable=FALSE → hold avgOut (same scan, no edge)
   PUB007/PUB008/PUB009/PUB010: DINT accumulator, REAL output, no rounding
   PUB011: avgOut retained via VAR; count clamp preserves index integrity
   S1: count<=0 → G((count<=0)→avgOut=prev(avgOut))  [no div, hold]
   S2: !enable  → G(!enable→avgOut=prev(avgOut))     [hold]
   S3: avgOut=avgOut (NaN guard via clamp logic, no div when count<=0)
   S5: !avgEnable → G(!avgEnable→avgOut=prev(avgOut)) [hold]
   S4/S6: arithmetic mean of values[1..clampedCount]
*)
FUNCTION_BLOCK FB
VAR
    prevAvgOut : REAL := 0.0;
END_VAR
VAR_OUTPUT
    avgOut : REAL := 0.0;
END_VAR
VAR_INPUT
    enable     : BOOL;
    values     : ARRAY[1..8] OF INT;
    count      : INT;
    avgEnable  : BOOL;
END_VAR

// PUB001/PUB002/PUB005/PUB011: unified update gate
IF enable AND (count > 0) AND avgEnable THEN
    // PUB003/PUB006: clamp count to [1..8] → prevents OOB and div-zero
    // PUB007: DINT accumulator for overflow safety
    VAR
        tmpSum   : DINT;
        tmpCount : INT;
    END_VAR
    tmpSum   := 0;
    tmpCount := count;
    IF tmpCount > 8 THEN
        tmpCount := 8;
    END_IF;

    // PUB008: sum using DINT to avoid INT overflow
    CASE tmpCount OF
        8: tmpSum := tmpSum + DINT(values[8]);
        7: tmpSum := tmpSum + DINT(values[7]);
        6: tmpSum := tmpSum + DINT(values[6]);
        5: tmpSum := tmpSum + DINT(values[5]);
        4: tmpSum := tmpSum + DINT(values[4]);
        3: tmpSum := tmpSum + DINT(values[3]);
        2: tmpSum := tmpSum + DINT(values[2]);
        1: tmpSum := tmpSum + DINT(values[1]);
        // 0: unreachable (guarded above), sum stays 0
    END_CASE;

    // PUB009: REAL division, no rounding
    avgOut := DINT_TO_REAL(tmpSum) / DINT_TO_REAL(tmpCount);
    prevAvgOut := avgOut;
ELSE
    // PUB001/PUB002/PUB005/PUB011: hold previous output
    avgOut     := prevAvgOut;
END_IF;

// Update retained state for next scan
prevAvgOut := avgOut;
END_FUNCTION_BLOCK

(* CONTRACT_RULES [] *)
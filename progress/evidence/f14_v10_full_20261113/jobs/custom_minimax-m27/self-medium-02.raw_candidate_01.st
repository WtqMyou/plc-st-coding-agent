FUNCTION_BLOCK FB
VAR_INPUT
    enable     : BOOL;
    rawValue   : REAL;
END_VAR
VAR_OUTPUT
    filteredValue : REAL;
    windowFull    : BOOL;
    sampleCount   : INT;
END_VAR
VAR
    buffer     : ARRAY[0..7] OF REAL;
    writeIdx   : INT := 0;
    tmp_sum    : REAL;
    tmp_i      : INT;
END_VAR
VAR_INPUT
END_VAR
VAR_OUTPUT
END_VAR
VAR
END_VAR
(* ENGINEERING_CONTRACT
   PUB.001-004   : inputs enable, rawValue; outputs filteredValue, windowFull, sampleCount
   PUB.005       : enable=TRUE per scan: push rawValue into 8-slot ring buffer
   PUB.006       : filteredValue = mean of actually-filled slots (no zero-fill)
   PUB.007       : on windowFull: FIFO eviction of oldest sample on each new push
   PUB.008       : sampleCount = current valid samples 0..8
   PUB.009       : windowFull = TRUE when sampleCount == 8, retains TRUE thereafter
   PUB.010       : enable=FALSE: clear buffer (sampleCount=0, windowFull=FALSE),
                   filteredValue RETAINED (last computed value held)
   PUB.011       : new enable period restarts count from 1 independently
   PUB.012-015   : formal properties S1-S7 encoded as LTL constraints
   PUB.016-038   : interface unchanged; no hidden timers or global variables

   Output retention table:
   | output        | activation             | retention      | reset                    |
   |---------------|------------------------|----------------|--------------------------|
   | filteredValue | every enabled scan     | holds on FALSE | not reset; retains last  |
   | sampleCount   | increments on each push| capped at 8    | forced 0 on enable=FALSE |
   | windowFull    | set TRUE at count=8    | holds TRUE     | forced FALSE on enable=FALSE|

   Same-scan priority: disable branch executes first; rising-edge start is
   indistinguishable from normal enabled scan since buffer is pre-cleared.
   Units: filteredValue REAL; sampleCount INT 0..8; windowFull BOOL.

   CONTRACT_RULES []
*)
tmp_sum := 0.0;
IF NOT enable THEN
    sampleCount   := 0;
    windowFull    := FALSE;
    writeIdx      := 0;
ELSE
    // Push current rawValue into ring buffer
    buffer[writeIdx] := rawValue;

    // Advance write pointer (mod 8), but sampleCount only increments up to 8
    writeIdx := (writeIdx + 1) MOD 8;
    IF sampleCount < 8 THEN
        sampleCount := sampleCount + 1;
    END_IF;

    // windowFull stays TRUE once set; set it only when count reaches 8
    IF sampleCount = 8 THEN
        windowFull := TRUE;
    END_IF;

    // Compute arithmetic mean of all valid samples currently in buffer
    tmp_sum := 0.0;
    FOR tmp_i := 0 TO sampleCount - 1 DO
        tmp_sum := tmp_sum + buffer[tmp_i];
    END_FOR;
    filteredValue := tmp_sum / TO_REAL(sampleCount);
END_IF;
END_FUNCTION_BLOCK
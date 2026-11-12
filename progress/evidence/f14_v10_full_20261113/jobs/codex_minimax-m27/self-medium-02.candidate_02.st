FUNCTION_BLOCK FB
VAR_INPUT
    enable   : BOOL;
    rawValue : REAL;
END_VAR

VAR_OUTPUT
    filteredValue : REAL;
    windowFull    : BOOL;
    sampleCount   : INT;
END_VAR

VAR
    buffer      : ARRAY[0..7] OF REAL;
    writeIndex  : INT := 0;
    bufferValid : BOOL := FALSE;
    tmp_sum     : REAL;
    tmp_i       : INT;
END_VAR

(*
ENGINEERING_CONTRACT
====================
State retention: filteredValue holds last computed average when disabled; cleared only on re-enable with fresh buffer.
Activation:     sampleCount increments per scan (0→8 max), windowFull TRUE when count=8, stays TRUE until enable=FALSE.
Explicit reset: enable=FALSE clears sampleCount and windowFull in same scan; filteredValue preserved.
Same-scan priority: All outputs updated before function returns.
Units/boundaries: sampleCount ∈ [0,8], buffer size = 8 REAL slots, circular overwrite when full.

Contract Rules: []
*)

IF enable THEN
    // First sample after disable: invalidate old buffer
    IF NOT bufferValid THEN
        writeIndex  := 0;
        sampleCount := 0;
    END_IF;
    bufferValid := TRUE;

    // Buffer not yet full: grow window
    IF sampleCount < 8 THEN
        buffer[writeIndex] := rawValue;
        sampleCount := sampleCount + 1;
        writeIndex := (writeIndex + 1) MOD 8;
    ELSE
        // Buffer full: overwrite oldest via circular index
        buffer[writeIndex] := rawValue;
        writeIndex := (writeIndex + 1) MOD 8;
    END_IF;

    // Compute filteredValue from valid samples only
    tmp_sum := 0.0;
    FOR tmp_i := 0 TO sampleCount - 1 DO
        tmp_sum := tmp_sum + buffer[tmp_i];
    END_FOR;
    filteredValue := tmp_sum / TO_REAL(sampleCount);
    windowFull := (sampleCount = 8);
ELSE
    // Disable: clear count and full flag, retain filteredValue and buffer
    bufferValid := FALSE;
    sampleCount := 0;
    windowFull  := FALSE;
END_IF;

END_FUNCTION_BLOCK
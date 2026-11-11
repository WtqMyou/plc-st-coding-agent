FUNCTION_BLOCK FB
VAR_INPUT
    enable : BOOL;
    rawValue : REAL;
END_VAR
VAR_OUTPUT
    filteredValue : REAL;
    windowFull    : BOOL;
    sampleCount   : INT;
END_VAR
VAR
    samples : ARRAY[0..7] OF REAL;
    i       : INT;
END_VAR

(* Shift in new sample when enabled *)
IF enable THEN
    samples[7] := samples[6];
    samples[6] := samples[5];
    samples[5] := samples[4];
    samples[4] := samples[3];
    samples[3] := samples[2];
    samples[2] := samples[1];
    samples[1] := samples[0];
    samples[0] := rawValue;

    IF sampleCount < 8 THEN
        sampleCount := sampleCount + 1;
    END_IF
END_IF

(* Clear buffer when disabled *)
IF NOT enable THEN
    sampleCount := 0;
END_IF

(* Window full flag *)
windowFull := (sampleCount = 8);

(* Compute moving average only while enabled *)
IF enable AND sampleCount > 0 THEN
    filteredValue := 0.0;
    FOR i := 0 TO sampleCount - 1 DO
        filteredValue := filteredValue + samples[i];
    END_FOR
    filteredValue := filteredValue / INT_TO_REAL(sampleCount);
END_IF

END_FUNCTION_BLOCK
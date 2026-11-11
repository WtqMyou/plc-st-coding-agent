FUNCTION_BLOCK FB
VAR_INPUT
    enable  : BOOL;
    rawValue: REAL;
END_VAR
VAR_OUTPUT
    filteredValue : REAL;
    windowFull    : BOOL;
    sampleCount   : INT;
END_VAR
VAR
    buffer    : ARRAY[0..7] OF REAL;
    writeIndex: INT := 0;
    sum       : REAL := 0.0;
END_VAR

IF NOT enable THEN
    sampleCount := 0;
    windowFull  := FALSE;
    writeIndex  := 0;
    sum         := 0.0;
ELSE
    IF sampleCount = 8 THEN
        sum := sum - buffer[writeIndex];
    END_IF

    buffer[writeIndex] := rawValue;
    sum := sum + rawValue;

    writeIndex := (writeIndex + 1) MOD 8;

    IF sampleCount < 8 THEN
        sampleCount := sampleCount + 1;
    END_IF;

    windowFull := (sampleCount = 8);

    filteredValue := sum / INT_TO_REAL(sampleCount);
END_IF

END_FUNCTION_BLOCK
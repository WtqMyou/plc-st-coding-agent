FUNCTION_BLOCK FB
VAR_INPUT
    enable : BOOL;
    rawValue : REAL;
END_VAR
VAR_OUTPUT
    filteredValue : REAL;
    windowFull : BOOL;
    sampleCount : INT;
END_VAR
VAR
    buffer : ARRAY[0..7] OF REAL;
    writeIndex : INT := 0;
    validCount : INT := 0;
    sum : REAL;
    i : INT;
END_VAR

IF enable THEN
    buffer[writeIndex] := rawValue;

    writeIndex := writeIndex + 1;
    IF writeIndex >= 8 THEN
        writeIndex := 0;
    END_IF;

    IF validCount < 8 THEN
        validCount := validCount + 1;
    END_IF;

    sum := 0.0;
    FOR i := 0 TO validCount - 1 DO
        sum := sum + buffer[i];
    END_FOR;

    filteredValue := sum / INT_TO_REAL(validCount);
    sampleCount := validCount;
    windowFull := validCount >= 8;
ELSE
    validCount := 0;
    writeIndex := 0;
    sampleCount := 0;
    windowFull := FALSE;
END_IF;

END_FUNCTION_BLOCK
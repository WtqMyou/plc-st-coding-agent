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
    loopIndex : INT;
END_VAR

IF enable THEN
    buffer[writeIndex] := rawValue;
    writeIndex := (writeIndex + 1) MOD 8;

    IF validCount < 8 THEN
        validCount := validCount + 1;
    END_IF;

    IF validCount = 1 THEN
        filteredValue := rawValue;
    ELSIF validCount = 2 THEN
        filteredValue := (buffer[0] + buffer[1]) / 2.0;
    ELSE
        sum := 0.0;
        FOR loopIndex := 0 TO validCount - 1 DO
            sum := sum + buffer[loopIndex];
        END_FOR;
        filteredValue := sum / INT_TO_REAL(validCount);
    END_IF;

    sampleCount := validCount;
    windowFull := validCount >= 8;
ELSE
    FOR loopIndex := 0 TO 7 DO
        buffer[loopIndex] := 0.0;
    END_FOR;

    writeIndex := 0;
    validCount := 0;
    sampleCount := 0;
    windowFull := FALSE;
END_IF
END_FUNCTION_BLOCK
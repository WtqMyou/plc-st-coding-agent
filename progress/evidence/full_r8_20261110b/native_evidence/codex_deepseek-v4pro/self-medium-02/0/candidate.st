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
    actualCount : INT := 0;
    writeIndex : INT := 0;
    sum : REAL;
    i : INT;
    idx : INT;
END_VAR

IF enable THEN
    buffer[writeIndex] := rawValue;

    IF actualCount < 8 THEN
        actualCount := actualCount + 1;
    END_IF

    sampleCount := actualCount;

    sum := 0.0;
    FOR i := 0 TO actualCount - 1 DO
        idx := writeIndex - i;
        IF idx < 0 THEN
            idx := idx + 8;
        END_IF
        sum := sum + buffer[idx];
    END_FOR

    filteredValue := sum / INT_TO_REAL(actualCount);
    windowFull := actualCount = 8;

    writeIndex := writeIndex + 1;
    IF writeIndex >= 8 THEN
        writeIndex := 0;
    END_IF
ELSE
    actualCount := 0;
    sampleCount := 0;
    windowFull := FALSE;
    writeIndex := 0;
END_IF
END_FUNCTION_BLOCK
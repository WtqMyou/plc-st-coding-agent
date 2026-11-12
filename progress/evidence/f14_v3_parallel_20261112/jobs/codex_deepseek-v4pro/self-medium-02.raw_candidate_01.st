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
    writeIndex : INT;
    bufIdx : INT;
    sum : REAL;
END_VAR

IF NOT enable THEN
    sampleCount := 0;
    windowFull := FALSE;
    writeIndex := 0;
    FOR bufIdx := 0 TO 7 DO
        buffer[bufIdx] := 0.0;
    END_FOR;
ELSE
    buffer[writeIndex] := rawValue;

    writeIndex := writeIndex + 1;
    IF writeIndex >= 8 THEN
        writeIndex := 0;
    END_IF;

    IF sampleCount < 8 THEN
        sampleCount := sampleCount + 1;
    END_IF;

    sum := 0.0;
    FOR bufIdx := 0 TO sampleCount - 1 DO
        sum := sum + buffer[bufIdx];
    END_FOR;

    filteredValue := sum / INT_TO_REAL(sampleCount);
    windowFull := sampleCount >= 8;
END_IF;

END_FUNCTION_BLOCK
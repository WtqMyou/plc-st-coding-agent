FUNCTION_BLOCK FB
VAR_INPUT
    enable      : BOOL;
    rawValue    : REAL;
END_VAR

VAR_OUTPUT
    filteredValue : REAL;
    windowFull    : BOOL;
    sampleCount   : INT;
END_VAR

VAR
    buffer       : ARRAY[0..7] OF REAL;
    writeIndex   : INT;
    sumValue     : REAL;
    index        : INT;
END_VAR

IF NOT enable THEN
    sampleCount := 0;
    windowFull := FALSE;
    writeIndex := 0;
    sumValue := 0.0;

    FOR index := 0 TO 7 DO
        buffer[index] := 0.0;
    END_FOR;
ELSE
    sumValue := 0.0;

    IF sampleCount < 8 THEN
        FOR index := 0 TO sampleCount - 1 DO
            sumValue := sumValue + buffer[index];
        END_FOR;

        sumValue := sumValue + rawValue;
        filteredValue := sumValue / INT_TO_REAL(sampleCount + 1);
    ELSE
        FOR index := 0 TO 7 DO
            sumValue := sumValue + buffer[index];
        END_FOR;

        sumValue := sumValue + rawValue - buffer[writeIndex];
        filteredValue := sumValue / 8.0;
    END_IF;

    buffer[writeIndex] := rawValue;

    IF writeIndex = 7 THEN
        writeIndex := 0;
    ELSE
        writeIndex := writeIndex + 1;
    END_IF;

    IF sampleCount < 8 THEN
        sampleCount := sampleCount + 1;
    END_IF;

    IF sampleCount >= 8 THEN
        windowFull := TRUE;
    END_IF;
END_IF

END_FUNCTION_BLOCK
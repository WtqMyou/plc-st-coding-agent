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
    sampleBuffer : ARRAY[0..7] OF REAL;
    writeIndex : INT;
    sampleCountState : INT;
    sum : REAL;
    i : INT;
END_VAR

IF NOT enable THEN
    sampleCountState := 0;
    writeIndex := 0;
    windowFull := FALSE;
    sampleCount := 0;
    sum := 0.0;
ELSE
    sampleBuffer[writeIndex] := rawValue;

    IF sampleCountState < 8 THEN
        sampleCountState := sampleCountState + 1;
    END_IF;

    writeIndex := writeIndex + 1;
    IF writeIndex >= 8 THEN
        writeIndex := 0;
    END_IF;

    sum := 0.0;
    FOR i := 0 TO sampleCountState - 1 DO
        sum := sum + sampleBuffer[i];
    END_FOR;

    IF sampleCountState > 0 THEN
        filteredValue := sum / REAL_TO_INT(sampleCountState);
    END_IF;
    sampleCount := sampleCountState;
    windowFull := sampleCountState >= 8;
END_IF
END_FUNCTION_BLOCK
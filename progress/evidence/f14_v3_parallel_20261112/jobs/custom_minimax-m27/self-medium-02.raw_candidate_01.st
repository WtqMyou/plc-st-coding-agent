FUNCTION_BLOCK FB
VAR
    buffer    : ARRAY[0..7] OF REAL;
    writeIndex : INT := 0;
END_VAR
VAR_OUTPUT
    filteredValue : REAL;
    windowFull    : BOOL;
    sampleCount   : INT;
END_VAR
VAR_INPUT
    enable   : BOOL;
    rawValue : REAL;
END_VAR

    IF enable THEN
        buffer[writeIndex] := rawValue;
        writeIndex := (writeIndex + 1) MOD 8;

        IF sampleCount < 8 THEN
            sampleCount := sampleCount + 1;
        END_IF;

        VAR i      : INT;
        VAR sum    : REAL;
        VAR idx    : INT;
        sum := 0.0;
        FOR i := 0 TO sampleCount - 1 DO
            idx    := (writeIndex - sampleCount + 8) MOD 8 + i;
            sum    := sum + buffer[idx];
        END_FOR;
        filteredValue := sum / INT_TO_REAL(sampleCount);

        windowFull := (sampleCount = 8);
    ELSE
        writeIndex := 0;
        sampleCount := 0;
        windowFull  := FALSE;
    END_IF;
END_FUNCTION_BLOCK
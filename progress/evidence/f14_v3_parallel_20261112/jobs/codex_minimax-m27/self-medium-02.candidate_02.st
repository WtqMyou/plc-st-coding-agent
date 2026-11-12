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
    buffer     : ARRAY[0..7] OF REAL;
    writeIndex : INT := 0;
    sum        : REAL := 0.0;
END_VAR

BEGIN
    IF enable THEN
        IF windowFull THEN
            sum := sum - buffer[writeIndex];
        ELSIF sampleCount > 0 THEN
            sum := sum - buffer[0];
        END_IF;

        sum := sum + rawValue;
        buffer[writeIndex] := rawValue;
        writeIndex := (writeIndex + 1) MOD 8;

        IF sampleCount < 8 THEN
            sampleCount := sampleCount + 1;
        END_IF;

        windowFull := (sampleCount = 8);
        filteredValue := sum / INT_TO_REAL(sampleCount);
    ELSE
        sampleCount := 0;
        windowFull  := FALSE;
        writeIndex  := 0;
        sum         := 0.0;
    END_IF;
END_FUNCTION_BLOCK
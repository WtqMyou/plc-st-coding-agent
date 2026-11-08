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
    buf : ARRAY[0..7] OF REAL;
    writeIndex : INT := 0;
    count : INT := 0;
    sum : REAL;
    i : INT;
END_VAR

IF NOT enable THEN
    count := 0;
    writeIndex := 0;
    windowFull := FALSE;
    sampleCount := 0;
ELSE
    buf[writeIndex] := rawValue;
    writeIndex := (writeIndex + 1) MOD 8;

    IF count < 8 THEN
        count := count + 1;
    END_IF;

    sum := 0.0;
    IF count > 0 THEN
        FOR i := 0 TO count - 1 DO
            sum := sum + buf[i];
        END_FOR;
        filteredValue := sum / INT_TO_REAL(count);
    END_IF;

    sampleCount := count;

    IF count >= 8 THEN
        windowFull := TRUE;
    ELSE
        windowFull := FALSE;
    END_IF;
END_IF;

END_FUNCTION_BLOCK
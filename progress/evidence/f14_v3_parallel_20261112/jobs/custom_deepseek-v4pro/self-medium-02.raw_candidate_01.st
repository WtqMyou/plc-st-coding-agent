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
    bufIdx : INT := 0;
    cnt : INT := 0;
    sum : REAL;
    i : INT;
END_VAR

IF enable THEN
    buffer[bufIdx] := rawValue;
    bufIdx := bufIdx + 1;
    IF bufIdx >= 8 THEN
        bufIdx := 0;
    END_IF;

    IF cnt < 8 THEN
        cnt := cnt + 1;
    END_IF;

    sum := 0.0;
    FOR i := 0 TO cnt - 1 DO
        sum := sum + buffer[i];
    END_FOR;

    filteredValue := sum / INT_TO_REAL(cnt);
    sampleCount := cnt;
    windowFull := (cnt >= 8);
ELSE
    cnt := 0;
    bufIdx := 0;
    sampleCount := 0;
    windowFull := FALSE;
END_IF;

END_FUNCTION_BLOCK
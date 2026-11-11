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
    wrIdx : INT := 0;
    cnt : INT := 0;
    sum : REAL;
    i : INT;
END_VAR

IF enable THEN
    buf[wrIdx] := rawValue;
    wrIdx := wrIdx + 1;
    IF wrIdx >= 8 THEN
        wrIdx := 0;
    END_IF;
    IF cnt < 8 THEN
        cnt := cnt + 1;
    END_IF;
    sum := 0.0;
    FOR i := 0 TO cnt - 1 DO
        sum := sum + buf[i];
    END_FOR;
    filteredValue := sum / INT_TO_REAL(cnt);
ELSE
    FOR i := 0 TO 7 DO
        buf[i] := 0.0;
    END_FOR;
    cnt := 0;
    wrIdx := 0;
    (* filteredValue intentionally unchanged *)
END_IF;

sampleCount := cnt;
windowFull := (cnt = 8);

END_FUNCTION_BLOCK
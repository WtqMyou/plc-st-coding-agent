FUNCTION_BLOCK FB
VAR_INPUT
    enable : BOOL;
    values : ARRAY[1..8] OF INT;
    count : INT;
    avgEnable : BOOL;
END_VAR
VAR_OUTPUT
    avgOut : REAL;
END_VAR
VAR
    lastAvg : REAL := 0.0;
    actualCount : INT := 0;
    sum : DINT := 0;
    idx : INT := 0;
END_VAR

IF enable AND avgEnable THEN
    IF count <= 0 THEN
        actualCount := 0;
    ELSIF count > 8 THEN
        actualCount := 8;
    ELSE
        actualCount := count;
    END_IF;

    IF actualCount > 0 THEN
        sum := 0;
        FOR idx := 1 TO actualCount BY 1 DO
            sum := sum + INT_TO_DINT(values[idx]);
        END_FOR;
        lastAvg := DINT_TO_REAL(sum) / INT_TO_REAL(actualCount);
    END_IF;
END_IF;

avgOut := lastAvg;

END_FUNCTION_BLOCK
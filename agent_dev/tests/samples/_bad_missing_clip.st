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
    i : INT;
    sum : DINT;
END_VAR
IF enable AND avgEnable AND count > 0 THEN
    sum := 0;
    FOR i := 1 TO count DO
        sum := sum + values[i];
    END_FOR
    avgOut := DINT_TO_REAL(sum) / INT_TO_REAL(count);
END_IF
END_FUNCTION_BLOCK

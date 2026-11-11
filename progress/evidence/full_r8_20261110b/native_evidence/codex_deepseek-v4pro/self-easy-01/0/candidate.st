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
    sum : DINT;
    validCount : INT;
    idx : INT;
END_VAR

IF enable AND avgEnable THEN
    IF count <= 0 THEN
        validCount := 0;
    ELSIF count > 8 THEN
        validCount := 8;
    ELSE
        validCount := count;
    END_IF

    IF validCount > 0 THEN
        sum := 0;
        FOR idx := 1 TO validCount DO
            sum := sum + INT_TO_DINT(values[idx]);
        END_FOR
        avgOut := DINT_TO_REAL(sum) / INT_TO_REAL(validCount);
    END_IF
END_IF

END_FUNCTION_BLOCK
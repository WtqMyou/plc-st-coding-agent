FUNCTION_BLOCK FB
VAR_INPUT
    enable      : BOOL;
    values      : ARRAY[1..8] OF INT;
    count       : INT;
    avgEnable   : BOOL;
END_VAR

VAR_OUTPUT
    avgOut      : REAL;
END_VAR

VAR
    sum         : DINT;
    i           : INT;
    safeCount   : INT;
END_VAR

// Calculate average only when all conditions are met
IF enable AND avgEnable AND (count > 0) THEN
    // Clamp count to array bounds [1, 8]
    IF count > 8 THEN
        safeCount := 8;
    ELSE
        safeCount := count;
    END_IF
    
    sum := 0;
    FOR i := 1 TO safeCount DO
        sum := sum + values[i];
    END_FOR
    avgOut := DINT_TO_REAL(sum) / INT_TO_REAL(safeCount);
END_IF
END_FUNCTION_BLOCK
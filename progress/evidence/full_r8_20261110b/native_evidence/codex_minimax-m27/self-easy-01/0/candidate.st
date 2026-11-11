FUNCTION_BLOCK FB
VAR_INPUT
    enable     : BOOL;
    values     : ARRAY[1..8] OF INT;
    count      : INT;
    avgEnable  : BOOL;
END_VAR
VAR_OUTPUT
    avgOut     : REAL;
END_VAR
VAR
    effectiveCount : INT;
    sumReal        : REAL;
    i              : INT;
END_VAR

effectiveCount := MIN(MAX(count, 0), 8);

IF enable AND avgEnable AND effectiveCount > 0 THEN
    sumReal := 0.0;
    FOR i := 1 TO effectiveCount DO
        sumReal := sumReal + INT_TO_REAL(values[i]);
    END_FOR
    avgOut := sumReal / TO_REAL(effectiveCount);
ELSE
    avgOut := avgOut;
END_IF
END_FUNCTION_BLOCK
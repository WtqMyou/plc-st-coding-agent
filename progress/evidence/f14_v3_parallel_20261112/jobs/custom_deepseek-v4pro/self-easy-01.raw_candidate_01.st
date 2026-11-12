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
    effectiveCount : INT;
    sum : DINT;
    i : INT;
    lastAvg : REAL;
END_VAR

IF enable AND avgEnable THEN
    IF count <= 0 THEN
        avgOut := lastAvg;
    ELSE
        effectiveCount := count;
        IF effectiveCount > 8 THEN
            effectiveCount := 8;
        END_IF;
        sum := 0;
        FOR i := 1 TO effectiveCount DO
            sum := sum + INT_TO_DINT(values[i]);
        END_FOR;
        lastAvg := DINT_TO_REAL(sum) / INT_TO_REAL(effectiveCount);
        avgOut := lastAvg;
    END_IF;
ELSE
    avgOut := lastAvg;
END_IF;

END_FUNCTION_BLOCK
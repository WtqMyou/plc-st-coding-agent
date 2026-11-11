FUNCTION_BLOCK FB
VAR_INPUT
    enable    : BOOL;
    values    : ARRAY[1..8] OF INT;
    count     : INT;
    avgEnable : BOOL;
END_VAR
VAR_OUTPUT
    avgOut    : REAL;
END_VAR
VAR
    sumValue   : DINT;
    sampleCount: INT;
    i          : INT;
END_VAR

IF enable AND avgEnable AND (count > 0) THEN
    sampleCount := count;

    IF sampleCount > 8 THEN
        sampleCount := 8;
    END_IF;

    sumValue := 0;

    FOR i := 1 TO sampleCount BY 1 DO
        sumValue := sumValue + INT_TO_DINT(values[i]);
    END_FOR;

    avgOut := DINT_TO_REAL(sumValue) / INT_TO_REAL(sampleCount);
END_IF;

END_FUNCTION_BLOCK
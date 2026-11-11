FUNCTION_BLOCK FB
VAR_INPUT
    enable    : BOOL;
    values    : ARRAY[1..8] OF INT;
    count     : INT;
    avgEnable : BOOL;
END_VAR

VAR_OUTPUT
    avgOut : REAL := 0.0;
END_VAR

VAR
    sumDint    : DINT;
    sampleCount : INT;
    index       : INT;
END_VAR

IF enable AND avgEnable AND (count > 0) THEN
    sampleCount := count;

    IF sampleCount > 8 THEN
        sampleCount := 8;
    END_IF;

    sumDint := 0;

    FOR index := 1 TO sampleCount DO
        sumDint := sumDint + INT_TO_DINT(values[index]);
    END_FOR;

    avgOut := DINT_TO_REAL(sumDint) / DINT_TO_REAL(sampleCount);
END_IF

END_FUNCTION_BLOCK
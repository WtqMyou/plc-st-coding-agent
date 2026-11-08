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
    total : LINT;
    sampleCount : INT;
    i : INT;
    avg : REAL;
END_VAR

avgOut := lastAvg;

IF enable AND avgEnable AND (count > 0) THEN
    sampleCount := count;
    IF sampleCount > 8 THEN
        sampleCount := 8;
    END_IF;

    total := 0;
    FOR i := 1 TO sampleCount DO
        total := total + INT_TO_LINT(values[i]);
    END_FOR;

    avg := LINT_TO_REAL(total) / INT_TO_REAL(sampleCount);
    avgOut := avg;
    lastAvg := avg;
END_IF;

END_FUNCTION_BLOCK
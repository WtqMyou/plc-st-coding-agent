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
    sampleCount : INT;
    total : LINT;
    idx : INT;
END_VAR

IF enable AND avgEnable AND (count > 0) THEN
    IF count > 8 THEN
        sampleCount := 8;
    ELSE
        sampleCount := count;
    END_IF;

    total := LINT#0;

    FOR idx := 1 TO sampleCount BY 1 DO
        total := total + INT_TO_LINT(values[idx]);
    END_FOR;

    avgOut := LINT_TO_REAL(total) / INT_TO_REAL(sampleCount);
END_IF;

END_FUNCTION_BLOCK
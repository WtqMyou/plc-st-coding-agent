FUNCTION_BLOCK FB
VAR_INPUT
    enable    : BOOL;
    values    : ARRAY[1..8] OF INT;
    count     : INT;
    avgEnable : BOOL;
END_VAR

VAR_OUTPUT
    avgOut : REAL;
END_VAR

VAR
    prev_avgOut : REAL;
    sum         : LINT;
    n           : INT;
END_VAR

IF enable AND avgEnable AND count > 0 THEN
    sum := 0;
    IF count > 8 THEN
        n := 8;
    ELSE
        n := count;
    END_IF;

    CASE n OF
        8: sum := sum + values[8];
        7: sum := sum + values[7];
        6: sum := sum + values[6];
        5: sum := sum + values[5];
        4: sum := sum + values[4];
        3: sum := sum + values[3];
        2: sum := sum + values[2];
        1: sum := sum + values[1];
    END_CASE;

    avgOut := LINT_TO_REAL(sum) / INT_TO_REAL(n);
    prev_avgOut := avgOut;
ELSE
    avgOut := prev_avgOut;
END_IF
END_FUNCTION_BLOCK
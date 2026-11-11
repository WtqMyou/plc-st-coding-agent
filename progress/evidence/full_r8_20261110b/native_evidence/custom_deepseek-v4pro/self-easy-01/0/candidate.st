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
    n : INT;
    sumDint : DINT;
    idx : INT;
END_VAR

IF enable AND avgEnable THEN
    IF count <= 0 THEN
        (* 保持 avgOut 不变 *)
    ELSE
        IF count > 8 THEN
            n := 8;
        ELSE
            n := count;
        END_IF;
        
        sumDint := 0;
        FOR idx := 1 TO n DO
            sumDint := sumDint + INT_TO_DINT(values[idx]);
        END_FOR;
        
        avgOut := DINT_TO_REAL(sumDint) / INT_TO_REAL(n);
    END_IF;
END_IF;

END_FUNCTION_BLOCK
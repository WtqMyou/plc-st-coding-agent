FUNCTION_BLOCK FB
VAR_INPUT
    pushEn : BOOL;
    pushItem : INT;
    popEn : BOOL;
END_VAR
VAR_IN_OUT
    fifo : ARRAY[1..8] OF INT;
END_VAR
VAR_OUTPUT
    count : INT;
    full : BOOL;
    empty : BOOL;
    head : INT;
END_VAR
VAR
    pushEn_prev : BOOL := FALSE;
    popEn_prev : BOOL := FALSE;
    pushRising : BOOL;
    popRising : BOOL;
    currentCount : INT := 0;
    i : INT;
END_VAR

pushRising := pushEn AND NOT pushEn_prev;
popRising := popEn AND NOT popEn_prev;

IF popRising AND (currentCount > 0) THEN
    IF currentCount > 1 THEN
        FOR i := 1 TO currentCount - 1 DO
            fifo[i] := fifo[i + 1];
        END_FOR;
    END_IF;
    fifo[currentCount] := 0;
    currentCount := currentCount - 1;
END_IF;

IF pushRising AND (currentCount < 8) THEN
    currentCount := currentCount + 1;
    fifo[currentCount] := pushItem;
END_IF;

pushEn_prev := pushEn;
popEn_prev := popEn;

count := currentCount;
full := (currentCount = 8);
empty := (currentCount = 0);

IF currentCount > 0 THEN
    head := fifo[1];
ELSE
    head := 0;
END_IF;

END_FUNCTION_BLOCK
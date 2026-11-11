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
    count : INT := 0;
    full : BOOL := FALSE;
    empty : BOOL := TRUE;
    head : INT := 0;
END_VAR
VAR
    pushRise : BOOL;
    popRise : BOOL;
    pushPrev : BOOL := FALSE;
    popPrev : BOOL := FALSE;
    workingCount : INT;
    idx : INT;
END_VAR

pushRise := pushEn AND NOT pushPrev;
popRise := popEn AND NOT popPrev;

workingCount := count;

IF popRise AND (workingCount > 0) THEN
    IF workingCount > 1 THEN
        FOR idx := 1 TO workingCount - 1 DO
            fifo[idx] := fifo[idx + 1];
        END_FOR;
    END_IF;
    fifo[workingCount] := 0;
    workingCount := workingCount - 1;
END_IF;

IF pushRise AND (workingCount < 8) THEN
    fifo[workingCount + 1] := pushItem;
    workingCount := workingCount + 1;
END_IF;

count := workingCount;
full := (workingCount = 8);
empty := (workingCount = 0);

IF workingCount > 0 THEN
    head := fifo[1];
ELSE
    head := 0;
END_IF;

pushPrev := pushEn;
popPrev := popEn;
END_FUNCTION_BLOCK
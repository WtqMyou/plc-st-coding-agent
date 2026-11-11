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
    lastPushEn : BOOL;
    lastPopEn : BOOL;
    queueCount : INT := 0;
    pushRise : BOOL;
    popRise : BOOL;
    popOk : BOOL;
    pushOk : BOOL;
    oldCount : INT;
    i : INT;
END_VAR

pushRise := pushEn AND NOT lastPushEn;
popRise := popEn AND NOT lastPopEn;

oldCount := queueCount;

popOk := popRise AND (oldCount > 0);
IF popOk THEN
    FOR i := 1 TO oldCount - 1 DO
        fifo[i] := fifo[i + 1];
    END_FOR;
    IF oldCount >= 1 THEN
        fifo[oldCount] := 0;
    END_IF;
    queueCount := oldCount - 1;
END_IF;

pushOk := pushRise AND (queueCount < 8);
IF pushOk THEN
    fifo[queueCount + 1] := pushItem;
    queueCount := queueCount + 1;
END_IF;

count := queueCount;
full := queueCount >= 8;
empty := queueCount <= 0;

IF empty THEN
    head := 0;
ELSE
    head := fifo[1];
END_IF;

lastPushEn := pushEn;
lastPopEn := popEn;
END_FUNCTION_BLOCK
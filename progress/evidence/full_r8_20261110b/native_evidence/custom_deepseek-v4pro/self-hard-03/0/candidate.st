FUNCTION_BLOCK FB
VAR_INPUT
    pushEn: BOOL;
    pushItem: INT;
    popEn: BOOL;
END_VAR
VAR_OUTPUT
    count: INT;
    full: BOOL;
    empty: BOOL;
    head: INT;
END_VAR
VAR_IN_OUT
    fifo: ARRAY[1..8] OF INT;
END_VAR
VAR
    prevPush: BOOL := FALSE;
    prevPop: BOOL := FALSE;
    actualCount: INT := 0;
    tempCount: INT;
    i: INT;
    tempFifo: ARRAY[1..8] OF INT;
END_VAR

tempFifo := fifo;
tempCount := actualCount;

IF (pushEn AND NOT prevPush) AND (popEn AND NOT prevPop) THEN
    IF tempCount > 0 THEN
        FOR i := 1 TO tempCount - 1 DO
            tempFifo[i] := tempFifo[i + 1];
        END_FOR
        tempFifo[tempCount] := pushItem;
    ELSE
        tempCount := 1;
        tempFifo[1] := pushItem;
    END_IF
ELSIF (pushEn AND NOT prevPush) THEN
    IF tempCount < 8 THEN
        tempCount := tempCount + 1;
        tempFifo[tempCount] := pushItem;
    END_IF
ELSIF (popEn AND NOT prevPop) THEN
    IF tempCount > 0 THEN
        FOR i := 1 TO tempCount - 1 DO
            tempFifo[i] := tempFifo[i + 1];
        END_FOR
        tempFifo[tempCount] := 0;
        tempCount := tempCount - 1;
    END_IF
END_IF

count := tempCount;
full := (tempCount = 8);
empty := (tempCount = 0);

IF tempCount = 0 THEN
    head := 0;
ELSE
    head := tempFifo[1];
END_IF

fifo := tempFifo;
actualCount := tempCount;

prevPush := pushEn;
prevPop := popEn;
END_FUNCTION_BLOCK
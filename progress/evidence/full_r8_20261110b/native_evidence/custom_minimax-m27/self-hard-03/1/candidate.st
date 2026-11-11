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
    prevPush : BOOL := FALSE;
    prevPop : BOOL := FALSE;
    risingPush : BOOL;
    risingPop : BOOL;
    prevCount : INT;
    doPop : BOOL;
    doPush : BOOL;
    i : INT;
END_VAR

risingPush := pushEn AND NOT prevPush;
risingPop := popEn AND NOT prevPop;
prevCount := count;

doPop := risingPop AND (prevCount > 0);
doPush := risingPush AND ((NOT doPop AND prevCount < 8) OR (doPop AND prevCount > 0));

IF doPop THEN
    FOR i := 1 TO count - 1 DO
        fifo[i] := fifo[i+1];
    END_FOR
    fifo[count] := 0;
END_IF

IF doPush THEN
    IF doPop THEN
        fifo[count] := pushItem;
    ELSE
        fifo[count + 1] := pushItem;
    END_IF
END_IF

count := prevCount + TO_INT(doPush) - TO_INT(doPop);
empty := (count = 0);
full := (count = 8);
head := fifo[1];

prevPush := pushEn;
prevPop := popEn;
END_FUNCTION_BLOCK
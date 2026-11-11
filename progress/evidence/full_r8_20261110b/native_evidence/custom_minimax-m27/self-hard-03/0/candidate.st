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
    newCount : INT;
    i : INT;
END_VAR

risingPush := pushEn AND NOT prevPush;
risingPop := popEn AND NOT prevPop;

prevCount := count;

doPop := risingPop AND (prevCount > 0);
doPush := risingPush AND (prevCount < 8);

newCount := prevCount;
IF doPush THEN
    newCount := newCount + 1;
END_IF
IF doPop THEN
    newCount := newCount - 1;
END_IF

IF doPop THEN
    FOR i := 1 TO 7 DO
        fifo[i] := fifo[i+1];
    END_FOR
    fifo[8] := 0;
END_IF

IF doPush THEN
    fifo[newCount] := pushItem;
END_IF

count := newCount;
empty := (count = 0);
full := (count = 8);
IF count > 0 THEN
    head := fifo[1];
ELSE
    head := 0;
END_IF

prevPush := pushEn;
prevPop := popEn;
END_FUNCTION_BLOCK
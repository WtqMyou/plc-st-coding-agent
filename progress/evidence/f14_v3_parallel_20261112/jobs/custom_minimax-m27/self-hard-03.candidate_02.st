FUNCTION_BLOCK FB
VAR_INPUT
    pushEn  : BOOL;
    pushItem: INT;
    popEn   : BOOL;
END_VAR

VAR_IN_OUT
    fifo : ARRAY[1..8] OF INT;
END_VAR

VAR_OUTPUT
    count : INT;
    full  : BOOL;
    empty : BOOL;
    head  : INT;
END_VAR

VAR
    prevPushEn : BOOL := FALSE;
    prevPopEn  : BOOL := FALSE;
    curCount   : INT  := 0;
    i          : INT;
    risingPush : BOOL;
    risingPop  : BOOL;
END_VAR

risingPush := pushEn AND NOT prevPushEn;
risingPop  := popEn  AND NOT prevPopEn;

prevPushEn := pushEn;
prevPopEn  := popEn;

IF risingPop THEN
    IF curCount > 0 THEN
        FOR i := 1 TO curCount - 1 DO
            fifo[i] := fifo[i+1];
        END_FOR;
        curCount := curCount - 1;
    END_IF;
END_IF;

IF risingPush THEN
    IF curCount < 8 THEN
        curCount := curCount + 1;
        fifo[curCount] := pushItem;
    END_IF;
END_IF;

count := curCount;
full  := (curCount = 8);
empty := (curCount = 0);
head  := fifo[1];

IF empty THEN
    head := 0;
END_IF;

END_FUNCTION_BLOCK
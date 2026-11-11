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
    count : INT := 0;
    full  : BOOL;
    empty : BOOL;
    head  : INT;
END_VAR
VAR
    prevPushEn : BOOL := FALSE;
    prevPopEn  : BOOL := FALSE;
    risingPush : BOOL;
    risingPop  : BOOL;
    i          : INT;
END_VAR

risingPush := pushEn AND NOT prevPushEn;
risingPop  := popEn  AND NOT prevPopEn;

IF risingPop AND count > 0 THEN
    count := count - 1;
    IF count >= 1 THEN
        FOR i := 1 TO count DO
            fifo[i] := fifo[i + 1];
        END_FOR
    END_IF
    fifo[count + 1] := 0;
END_IF

IF risingPush AND count < 8 THEN
    count := count + 1;
    fifo[count] := pushItem;
END_IF

full  := (count = 8);
empty := (count = 0);
head  := fifo[1];

prevPushEn := pushEn;
prevPopEn  := popEn;

END_FUNCTION_BLOCK
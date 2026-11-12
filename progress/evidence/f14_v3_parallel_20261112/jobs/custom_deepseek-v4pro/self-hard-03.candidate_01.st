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
    prevCount : INT := 0;
    oldF : ARRAY[1..8] OF INT;
    newArr : ARRAY[1..8] OF INT;
    risingPush : BOOL;
    risingPop : BOOL;
    popAct : BOOL;
    pushAct : BOOL;
    afterPopCount : INT;
    newCount : INT;
    i : INT;
END_VAR

risingPush := pushEn AND NOT prevPush;
risingPop := popEn AND NOT prevPop;

FOR i := 1 TO 8 DO
    oldF[i] := fifo[i];
END_FOR;

popAct := risingPop AND (prevCount > 0);

IF popAct THEN
    afterPopCount := prevCount - 1;
ELSE
    afterPopCount := prevCount;
END_IF;

pushAct := risingPush AND (afterPopCount < 8);

IF pushAct THEN
    newCount := afterPopCount + 1;
ELSE
    newCount := afterPopCount;
END_IF;

FOR i := 1 TO 8 DO
    newArr[i] := 0;
END_FOR;

IF popAct THEN
    IF pushAct THEN
        FOR i := 1 TO prevCount - 1 DO
            newArr[i] := oldF[i + 1];
        END_FOR;
        newArr[prevCount] := pushItem;
    ELSE
        FOR i := 1 TO prevCount - 1 DO
            newArr[i] := oldF[i + 1];
        END_FOR;
    END_IF;
ELSE
    IF pushAct THEN
        FOR i := 1 TO prevCount DO
            newArr[i] := oldF[i];
        END_FOR;
        newArr[prevCount + 1] := pushItem;
    ELSE
        FOR i := 1 TO prevCount DO
            newArr[i] := oldF[i];
        END_FOR;
    END_IF;
END_IF;

FOR i := 1 TO 8 DO
    fifo[i] := newArr[i];
END_FOR;

IF newCount > 0 THEN
    head := newArr[1];
ELSE
    head := 0;
END_IF;

count := newCount;
full := (newCount = 8);
empty := (newCount = 0);

prevPush := pushEn;
prevPop := popEn;
prevCount := newCount;
END_FUNCTION_BLOCK
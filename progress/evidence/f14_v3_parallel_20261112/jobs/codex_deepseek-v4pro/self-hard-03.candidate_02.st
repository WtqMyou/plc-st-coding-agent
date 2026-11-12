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
    qcnt : INT := 0;
    pushPrev : BOOL := FALSE;
    popPrev : BOOL := FALSE;
    pushRise : BOOL;
    popRise : BOOL;
    idx : INT;
END_VAR

pushRise := pushEn AND NOT pushPrev;
popRise := popEn AND NOT popPrev;

IF popRise AND qcnt > 0 THEN
    FOR idx := 1 TO qcnt - 1 DO
        fifo[idx] := fifo[idx + 1];
    END_FOR;
    qcnt := qcnt - 1;
END_IF;

IF pushRise AND qcnt < 8 THEN
    fifo[qcnt + 1] := pushItem;
    qcnt := qcnt + 1;
END_IF;

count := qcnt;
full := (qcnt = 8);
empty := (qcnt = 0);

IF qcnt = 0 THEN
    head := 0;
ELSE
    head := fifo[1];
END_IF;

pushPrev := pushEn;
popPrev := popEn;
END_FUNCTION_BLOCK
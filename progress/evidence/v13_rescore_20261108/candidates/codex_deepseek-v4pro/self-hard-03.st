FUNCTION_BLOCK FB
VAR_INPUT
    pushEn   : BOOL;
    pushItem : INT;
    popEn    : BOOL;
END_VAR
VAR_OUTPUT
    count  : INT;
    full   : BOOL;
    empty  : BOOL;
    head   : INT;
END_VAR
VAR_IN_OUT
    fifo : ARRAY[1..8] OF INT;
END_VAR
VAR
    pushPrev : BOOL;
    popPrev  : BOOL;
    pushRise : BOOL;
    popRise  : BOOL;
    i        : INT;
END_VAR

pushRise := pushEn AND NOT pushPrev;
popRise  := popEn AND NOT popPrev;
pushPrev := pushEn;
popPrev  := popEn;

IF popRise THEN
    IF count > 0 THEN
        FOR i := 1 TO 7 DO
            fifo[i] := fifo[i + 1];
        END_FOR;
        fifo[8] := 0;
        count := count - 1;
    END_IF;
END_IF;

IF pushRise THEN
    IF count < 8 THEN
        fifo[count + 1] := pushItem;
        count := count + 1;
    END_IF;
END_IF;

full := count >= 8;
empty := count <= 0;

IF count <= 0 THEN
    head := 0;
ELSE
    head := fifo[1];
END_IF;

END_FUNCTION_BLOCK
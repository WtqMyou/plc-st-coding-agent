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
    wasPush : BOOL;
    wasPop : BOOL;
    put : BOOL;
    take : BOOL;
    i : INT;
END_VAR

put := pushEn AND NOT wasPush;
take := popEn AND NOT wasPop;
wasPush := pushEn;
wasPop := popEn;

IF take AND count > 0 THEN
    FOR i := 1 TO count - 1 DO
        fifo[i] := fifo[i + 1];
    END_FOR;
    count := count - 1;
END_IF;
IF put AND count < 8 THEN
    count := count + 1;
    fifo[count] := pushItem;
END_IF;
full := count = 8;
empty := count = 0;
IF empty THEN
    head := 0;
ELSE
    head := fifo[1];
END_IF;
END_FUNCTION_BLOCK

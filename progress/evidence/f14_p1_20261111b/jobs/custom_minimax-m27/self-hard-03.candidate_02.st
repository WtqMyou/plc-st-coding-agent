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
    prevPush : BOOL;
    prevPop  : BOOL;
    i        : INT;
END_VAR

    // pop rising edge: remove first element if not empty
    IF popEn AND NOT prevPop THEN
        IF count > 0 THEN
            FOR i := 1 TO count - 1 DO
                fifo[i] := fifo[i + 1];
            END_FOR
            fifo[count] := 0;
            count := count - 1;
        END_IF
    END_IF

    // push rising edge: add item if not full
    IF pushEn AND NOT prevPush THEN
        IF count < 8 THEN
            count := count + 1;
            fifo[count] := pushItem;
        END_IF
    END_IF

    // outputs
    full  := (count = 8);
    empty := (count = 0);
    head  := 0;
    IF NOT empty THEN
        head := fifo[1];
    END_IF

    // update edge detection history
    prevPush := pushEn;
    prevPop  := popEn;
END_FUNCTION_BLOCK
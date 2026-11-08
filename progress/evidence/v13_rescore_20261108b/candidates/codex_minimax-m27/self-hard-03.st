FUNCTION_BLOCK FB
VAR_INPUT
    pushEn  : BOOL;
    pushItem: INT;
    popEn   : BOOL;
END_VAR

VAR_OUTPUT
    count : INT := 0;
    full  : BOOL;
    empty : BOOL;
    head  : INT;
END_VAR

VAR_IN_OUT
    fifo : ARRAY[1..8] OF INT;
END_VAR

VAR
    prevPushEn : BOOL := FALSE;
    prevPopEn  : BOOL := FALSE;
    i          : INT;
END_VAR

// Priority: pop first, then push (when both are rising edges)
IF popEn AND NOT prevPopEn THEN
    IF count > 0 THEN
        FOR i := 1 TO count - 1 DO
            fifo[i] := fifo[i + 1];
        END_FOR;
        fifo[count] := 0;
        count := count - 1;
    END_IF;
END_IF;

IF pushEn AND NOT prevPushEn THEN
    IF count < 8 THEN
        count := count + 1;
        fifo[count] := pushItem;
    END_IF;
END_IF;

// Update edge detection history for next scan
prevPushEn := pushEn;
prevPopEn  := popEn;

// Compute outputs
full  := (count = 8);
empty := (count = 0);
head  := fifo[1];

END_FUNCTION_BLOCK
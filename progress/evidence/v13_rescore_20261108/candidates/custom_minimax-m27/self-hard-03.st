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
    prevPushEn : BOOL;
    prevPopEn  : BOOL;
    risingPush : BOOL;
    risingPop  : BOOL;
    i          : INT;
END_VAR

// Step 1: Rising edge detection
risingPush := pushEn AND NOT prevPushEn;
risingPop  := popEn  AND NOT prevPopEn;

// Step 2: Pop first when both edges occur in same cycle
IF risingPop THEN
    IF count > 0 THEN
        FOR i := 1 TO count - 1 DO
            fifo[i] := fifo[i + 1];
        END_FOR
        fifo[count] := 0;
        count := count - 1;
    END_IF
END_IF

// Step 3: Push after pop
IF risingPush THEN
    IF count < 8 THEN
        count := count + 1;
        fifo[count] := pushItem;
    END_IF
END_IF

// Step 4: Update outputs
empty := (count = 0);
full  := (count = 8);

IF count > 0 THEN
    head := fifo[1];
ELSE
    head := 0;
END_IF

// Step 5: Update edge history for next scan
prevPushEn := pushEn;
prevPopEn  := popEn;

END_FUNCTION_BLOCK
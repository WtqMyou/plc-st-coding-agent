FUNCTION_BLOCK FB
VAR_INPUT
    pushEn: BOOL;
    pushItem: INT;
    popEn: BOOL;
END_VAR

VAR_IN_OUT
    fifo: ARRAY[1..8] OF INT;
END_VAR

VAR_OUTPUT
    count: INT := 0;
    full: BOOL := FALSE;
    empty: BOOL := TRUE;
    head: INT := 0;
END_VAR

VAR
    prevPushEn: BOOL := FALSE;
    prevPopEn: BOOL := FALSE;
END_VAR

VAR
    risingPush: BOOL;
    risingPop: BOOL;
    i: INT;
END_VAR

// Detect rising edges
risingPush := pushEn AND NOT prevPushEn;
risingPop := popEn AND NOT prevPopEn;

// Process in order: pop first, then push
// POP: only if queue not empty
IF risingPop AND count > 0 THEN
    // Shift left if more than one element
    IF count > 1 THEN
        FOR i := 1 TO count - 1 DO
            fifo[i] := fifo[i + 1];
        END_FOR;
    END_IF;
    // Decrement count
    count := count - 1;
END_IF;

// PUSH: only if queue not full
IF risingPush AND count < 8 THEN
    count := count + 1;
    fifo[count] := pushItem;
END_IF;

// Update outputs
full := (count = 8);
empty := (count = 0);
IF count > 0 THEN
    head := fifo[1];
ELSE
    head := 0;
END_IF;

// Save current state for next cycle
prevPushEn := pushEn;
prevPopEn := popEn;

END_FUNCTION_BLOCK
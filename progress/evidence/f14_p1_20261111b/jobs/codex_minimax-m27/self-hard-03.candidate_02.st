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
    i          : INT;
END_VAR

// ---------------------------------------------------------------------------
// Rising edge detection
// ---------------------------------------------------------------------------
VAR
    risingPush : BOOL;
    risingPop  : BOOL;
END_VAR

risingPush := pushEn AND NOT prevPushEn;
risingPop  := popEn  AND NOT prevPopEn;

// ---------------------------------------------------------------------------
// FIFO logic: pop first, then push
// ---------------------------------------------------------------------------

// 1) Pop on rising edge (non-empty only)
IF risingPop AND count > 0 THEN
    FOR i := 1 TO count - 1 DO
        fifo[i] := fifo[i + 1];
    END_FOR;
    count := count - 1;
END_IF;

// 2) Push on rising edge (only if space available)
IF risingPush AND count < 8 THEN
    count        := count + 1;
    fifo[count]  := pushItem;
END_IF;

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
full  := (count = 8);
empty := (count = 0);

IF count = 0 THEN
    head := 0;
ELSE
    head := fifo[1];
END_IF;

// ---------------------------------------------------------------------------
// Save button histories for next cycle
// ---------------------------------------------------------------------------
prevPushEn := pushEn;
prevPopEn  := popEn;

END_FUNCTION_BLOCK
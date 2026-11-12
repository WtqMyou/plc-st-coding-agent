FUNCTION_BLOCK FB_FIFO_Queue
VAR_INPUT
    enqueue  : BOOL;
    dequeue  : BOOL;
    reset    : BOOL;
END_VAR
VAR_OUTPUT
    elementCount : DINT := 0;
    status       : WORD := 16#0000;
END_VAR
VAR_IN_OUT
    item   : VARIANT;
    buffer : VARIANT;
END_VAR
VAR
    head         : DINT := 0;
    tail         : DINT := 0;
    capacity     : DINT := 0;
    prevEnqueue  : BOOL := FALSE;
    prevDequeue  : BOOL := FALSE;
    initDone     : BOOL := FALSE;
END_VAR

// Initialize capacity from buffer array bounds on first invocation
IF NOT initDone THEN
    capacity := __GETUPPERBOUND(buffer, 1) + 1;
    initDone := TRUE;
END_IF

// Reset takes priority over all other operations
IF reset THEN
    head := 0;
    tail := 0;
    elementCount := 0;
    status := 16#0000;
    prevEnqueue := FALSE;
    prevDequeue := FALSE;
    RETURN;
END_IF;

// Rising edge detection for enqueue
IF enqueue AND NOT prevEnqueue THEN
    prevEnqueue := TRUE;
    IF elementCount >= capacity THEN
        status := 16#8002;
    ELSE
        __SETATINDEX(buffer, tail, item);
        tail := (tail + 1) MOD capacity;
        elementCount := elementCount + 1;
        status := 16#0000;
    END_IF;
ELSE
    prevEnqueue := enqueue;
END_IF;

// Rising edge detection for dequeue
IF dequeue AND NOT prevDequeue THEN
    prevDequeue := TRUE;
    IF elementCount <= 0 THEN
        status := 16#8001;
    ELSE
        item := __GETATINDEX(buffer, head);
        head := (head + 1) MOD capacity;
        elementCount := elementCount - 1;
        status := 16#0000;
    END_IF;
ELSE
    prevDequeue := dequeue;
END_IF;

// Set status to no-error if no operation was performed this cycle
IF NOT reset AND NOT (enqueue AND NOT prevEnqueue) AND NOT (dequeue AND NOT prevDequeue) THEN
    status := 16#0000;
END_IF;

END_FUNCTION_BLOCK
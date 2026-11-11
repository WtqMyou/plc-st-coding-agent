FUNCTION_BLOCK FB
VAR_INPUT
    enqueue  : BOOL;
    dequeue  : BOOL;
    reset    : BOOL;
    capacity : DINT;
END_VAR
VAR_OUTPUT
    elementCount : DINT := 0;
    status       : WORD  := 16#0000;
END_VAR
VAR_IN_OUT
    item   : DINT;
    buffer : ARRAY[1..4] OF DINT;
END_VAR
VAR
    head       : DINT := 0;
    tail       : DINT := 0;
    prevEnqueue : BOOL := FALSE;
    prevDequeue : BOOL := FALSE;
END_VAR

// Priority 1: Reset (level-triggered, takes precedence)
IF reset THEN
    elementCount := 0;
    head := 0;
    tail := 0;
    status := 16#0000;
// Priority 2: Enqueue (rising edge, rejected if dequeue is active)
ELSIF enqueue AND NOT prevEnqueue AND NOT dequeue THEN
    IF elementCount < capacity THEN
        buffer[tail + 1] := item;
        tail := (tail + 1) MOD capacity;
        elementCount := elementCount + 1;
        status := 16#0000;
    ELSE
        status := 16#8002;
    END_IF;
// Priority 3: Dequeue (rising edge, rejected if enqueue is active)
ELSIF dequeue AND NOT prevDequeue AND NOT enqueue THEN
    IF elementCount > 0 THEN
        item := buffer[head + 1];
        head := (head + 1) MOD capacity;
        elementCount := elementCount - 1;
        status := 16#0000;
    ELSE
        status := 16#8001;
    END_IF;
ELSE
    status := 16#0000;
END_IF;

// Update edge-detection history
prevEnqueue := enqueue;
prevDequeue := dequeue;

END_FUNCTION_BLOCK
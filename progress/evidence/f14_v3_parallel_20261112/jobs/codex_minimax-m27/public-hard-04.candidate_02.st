FUNCTION_BLOCK FB_FIFOQueue
VAR_INPUT
    enqueue : BOOL;
    dequeue : BOOL;
    reset   : BOOL;
END_VAR
VAR_OUTPUT
    elementCount : DINT;
    status       : WORD;
END_VAR
VAR_IN_OUT
    item   : VARIANT;
    buffer : VARIANT;
END_VAR
VAR
    head       : DINT := 0;
    tail       : DINT := 0;
    capacity   : DINT := 0;
    prevEnqueue : BOOL := FALSE;
    prevDequeue : BOOL := FALSE;
    prevReset   : BOOL := FALSE;
    firstCall   : BOOL := TRUE;
END_VAR

status := 16#0000;

IF firstCall THEN
    firstCall := FALSE;
    prevEnqueue := enqueue;
    prevDequeue := dequeue;
    prevReset := reset;
    RETURN;
END_IF;

IF __ISARRAY(buffer) THEN
    capacity := __UBOUND(buffer, 1) - __LBBOUND(buffer, 1) + 1;
END_IF;

IF reset AND NOT prevReset THEN
    head := 0;
    tail := 0;
    elementCount := 0;
ELSIF enqueue AND NOT prevEnqueue THEN
    IF elementCount < capacity THEN
        buffer[tail] := item;
        tail := (tail + 1) MOD capacity;
        elementCount := elementCount + 1;
    ELSE
        status := 16#8002;
    END_IF;
ELSIF dequeue AND NOT prevDequeue THEN
    IF elementCount > 0 THEN
        item := buffer[head];
        head := (head + 1) MOD capacity;
        elementCount := elementCount - 1;
    ELSE
        status := 16#8001;
    END_IF;
END_IF;

prevEnqueue := enqueue;
prevDequeue := dequeue;
prevReset := reset;
END_FUNCTION_BLOCK
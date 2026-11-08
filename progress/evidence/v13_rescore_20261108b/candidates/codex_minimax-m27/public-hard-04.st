FUNCTION_BLOCK FB
VAR_INPUT
    enqueue  : BOOL;
    dequeue  : BOOL;
    reset    : BOOL;
    capacity : DINT;
END_VAR
VAR_OUTPUT
    elementCount : DINT := 0;
    status       : WORD := 16#0000;
END_VAR
VAR_IN_OUT
    item   : DINT;
    buffer : ARRAY[1..4] OF DINT;
END_VAR
VAR
    head        : DINT := 1;
    tail        : DINT := 1;
    lastEnqueue : BOOL := FALSE;
    lastDequeue : BOOL := FALSE;
    lastReset   : BOOL := FALSE;
END_VAR

status := 16#0000;

IF reset THEN
    elementCount := 0;
    head := 1;
    tail := 1;
ELSIF NOT lastReset THEN
    IF enqueue AND NOT lastEnqueue THEN
        IF elementCount < capacity THEN
            buffer[tail] := item;
            elementCount := elementCount + 1;
            tail := (tail MOD capacity) + 1;
        ELSE
            status := 16#8002;
        END_IF
    ELSIF dequeue AND NOT lastDequeue THEN
        IF elementCount > 0 THEN
            item := buffer[head];
            elementCount := elementCount - 1;
            head := (head MOD capacity) + 1;
        ELSE
            status := 16#8001;
        END_IF
    END_IF
END_IF

lastEnqueue := enqueue;
lastDequeue := dequeue;
lastReset   := reset;
END_FUNCTION_BLOCK
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
    head         : DINT := 1;
    tail         : DINT := 1;
    enqueue_prev : BOOL := FALSE;
    dequeue_prev : BOOL := FALSE;
END_VAR

// Reset takes priority
IF reset THEN
    elementCount := 0;
    head := 1;
    tail := 1;
    status := 16#0000;
ELSE
    // Rising edge detection for enqueue
    IF NOT enqueue_prev AND enqueue THEN
        IF elementCount < capacity THEN
            buffer[((tail - 1) MOD capacity) + 1] := item;
            tail := (tail MOD capacity) + 1;
            elementCount := elementCount + 1;
            status := 16#0000;
        ELSE
            status := 16#8002;
        END_IF
    END_IF

    // Rising edge detection for dequeue
    IF NOT dequeue_prev AND dequeue THEN
        IF elementCount > 0 THEN
            item := buffer[((head - 1) MOD capacity) + 1];
            head := (head MOD capacity) + 1;
            elementCount := elementCount - 1;
            status := 16#0000;
        ELSE
            status := 16#8001;
        END_IF
    END_IF

    // No error when no rising edge and no other condition
    IF enqueue_prev = enqueue AND dequeue_prev = dequeue THEN
        status := 16#0000;
    END_IF
END_IF

// Update edge detection history
enqueue_prev := enqueue;
dequeue_prev := dequeue;
END_FUNCTION_BLOCK
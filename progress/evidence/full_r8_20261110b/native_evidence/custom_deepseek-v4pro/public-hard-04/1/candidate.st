FUNCTION_BLOCK FB
VAR_INPUT
    enqueue: BOOL;
    dequeue: BOOL;
    reset: BOOL;
    capacity: DINT;
END_VAR
VAR_OUTPUT
    elementCount: DINT;
    status: WORD;
END_VAR
VAR_IN_OUT
    item: DINT;
    buffer: ARRAY[1..4] OF DINT;
END_VAR
VAR
    head: DINT := 1;
    tail: DINT := 1;
    count: DINT := 0;
    lastEnqueue: BOOL := FALSE;
    lastDequeue: BOOL := FALSE;
    enqRising: BOOL;
    deqRising: BOOL;
END_VAR

IF reset THEN
    count := 0;
    head := 1;
    tail := 1;
    elementCount := 0;
    status := 0;
    lastEnqueue := enqueue;
    lastDequeue := dequeue;
ELSE
    enqRising := enqueue AND NOT lastEnqueue;
    deqRising := dequeue AND NOT lastDequeue;
    
    status := 0;
    
    IF enqRising AND NOT deqRising THEN
        IF count < capacity THEN
            buffer[tail] := item;
            tail := tail + 1;
            IF tail > capacity THEN
                tail := 1;
            END_IF;
            count := count + 1;
        ELSE
            status := 16#8002;
        END_IF;
    ELSIF deqRising AND NOT enqRising THEN
        IF count > 0 THEN
            item := buffer[head];
            head := head + 1;
            IF head > capacity THEN
                head := 1;
            END_IF;
            count := count - 1;
        ELSE
            status := 16#8001;
        END_IF;
    ELSIF enqRising AND deqRising THEN
        (* Both rising edges in same invocation: ignore both, keep status 0 *)
        status := 0;
    END_IF;
    
    elementCount := count;
    lastEnqueue := enqueue;
    lastDequeue := dequeue;
END_IF;

END_FUNCTION_BLOCK
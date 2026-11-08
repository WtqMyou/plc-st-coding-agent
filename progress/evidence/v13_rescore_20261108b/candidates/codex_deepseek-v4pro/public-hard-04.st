FUNCTION_BLOCK FB
VAR_INPUT
    enqueue : BOOL;
    dequeue : BOOL;
    reset : BOOL;
    capacity : DINT;
END_VAR
VAR_OUTPUT
    elementCount : DINT;
    status : WORD;
END_VAR
VAR_IN_OUT
    item : DINT;
    buffer : ARRAY[1..4] OF DINT;
END_VAR
VAR
    head : DINT := 1;
    tail : DINT := 1;
    count : DINT := 0;
    prevEnqueue : BOOL := FALSE;
    prevDequeue : BOOL := FALSE;
    enqRise : BOOL := FALSE;
    deqRise : BOOL := FALSE;
END_VAR

elementCount := count;
status := 16#0000;

enqRise := enqueue AND NOT prevEnqueue;
deqRise := dequeue AND NOT prevDequeue;

IF reset THEN
    count := 0;
    head := 1;
    tail := 1;
    elementCount := count;
ELSIF NOT (enqRise AND deqRise) THEN
    IF enqRise THEN
        IF count < capacity THEN
            buffer[tail] := item;
            tail := tail + 1;
            IF tail > capacity THEN
                tail := 1;
            END_IF
            count := count + 1;
        ELSE
            status := 16#8002;
        END_IF
    END_IF

    IF deqRise THEN
        IF count > 0 THEN
            item := buffer[head];
            head := head + 1;
            IF head > capacity THEN
                head := 1;
            END_IF
            count := count - 1;
        ELSE
            status := 16#8001;
        END_IF
    END_IF

    elementCount := count;
END_IF

prevEnqueue := enqueue;
prevDequeue := dequeue;

END_FUNCTION_BLOCK
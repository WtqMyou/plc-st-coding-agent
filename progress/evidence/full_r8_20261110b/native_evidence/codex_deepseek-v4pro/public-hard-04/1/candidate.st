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
    count : DINT := 0;
    head : DINT := 1;
    tail : DINT := 1;
    enPrev : BOOL := FALSE;
    dePrev : BOOL := FALSE;
    enRise : BOOL;
    deRise : BOOL;
END_VAR

enRise := enqueue AND NOT enPrev;
deRise := dequeue AND NOT dePrev;

IF reset THEN
    count := 0;
    head := 1;
    tail := 1;
    status := 16#0000;
ELSE
    status := 16#0000;

    IF enRise AND NOT dequeue THEN
        IF count < capacity THEN
            buffer[tail] := item;
            IF tail >= capacity THEN
                tail := 1;
            ELSE
                tail := tail + 1;
            END_IF;
            count := count + 1;
        ELSE
            status := 16#8002;
        END_IF;
    ELSIF deRise AND NOT enqueue THEN
        IF count > 0 THEN
            item := buffer[head];
            IF head >= capacity THEN
                head := 1;
            ELSE
                head := head + 1;
            END_IF;
            count := count - 1;
        ELSE
            status := 16#8001;
        END_IF;
    END_IF;
END_IF;

enPrev := enqueue;
dePrev := dequeue;
elementCount := count;

END_FUNCTION_BLOCK
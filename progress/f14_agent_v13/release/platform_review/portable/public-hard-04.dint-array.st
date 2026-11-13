(* Separate DINT binding for CODESYS target evaluation. *)
FUNCTION_BLOCK FB
VAR_INPUT
    enqueue : BOOL;
    dequeue : BOOL;
    reset : BOOL;
END_VAR
VAR_OUTPUT
    elementCount : DINT;
    status : WORD;
END_VAR
VAR_IN_OUT
    item : DINT;
    buffer : ARRAY[*] OF DINT;
END_VAR
VAR
    cap : DINT;
    count : DINT;
    head : DINT;
    tail : DINT;
    enPrev : BOOL;
    dePrev : BOOL;
    enEdge : BOOL;
    deEdge : BOOL;
END_VAR

cap := UPPER_BOUND(buffer, 1) - LOWER_BOUND(buffer, 1) + 1;
IF count < 0 THEN
    count := 0;
END_IF;
IF head < 1 THEN
    head := 1;
END_IF;
enEdge := enqueue AND NOT enPrev;
enPrev := enqueue;
deEdge := dequeue AND NOT dePrev;
dePrev := dequeue;
status := 16#0000;

IF reset THEN
    count := 0;
    head := 1;
ELSIF enEdge THEN
    IF (cap <= 0) OR (count >= cap) THEN
        status := 16#8002;
    ELSE
        (* Add head and count only when the sum fits in the positive DINT cap. *)
        IF count > cap - head THEN
            tail := count - (cap - head);
        ELSE
            tail := head + count;
        END_IF;
        buffer[LOWER_BOUND(buffer, 1) + (tail - 1)] := item;
        count := count + 1;
    END_IF;
ELSIF deEdge THEN
    IF count <= 0 THEN
        status := 16#8001;
    ELSE
        item := buffer[LOWER_BOUND(buffer, 1) + (head - 1)];
        IF head = cap THEN
            head := 1;
        ELSE
            head := head + 1;
        END_IF;
        count := count - 1;
    END_IF;
END_IF;
elementCount := count;
END_FUNCTION_BLOCK

// FIFO Queue Implementation - CODESYS 3.5
// PUB001: Rising edge enqueue appends item to tail if not full
// PUB002: Rising edge dequeue removes front to item if not empty; caller must not combine enq+deq
// PUB003: reset=TRUE empties queue, sets elementCount=0; takes priority; buffer values may persist
// PUB004: elementCount=0..capacity; 0=empty, capacity=full
// PUB005: Reject deq when empty or enq when full; leave queue/item unchanged; status reports reason
// PUB006: status=16#0000(no err), 16#8001(deq rejected empty), 16#8002(enq rejected full)
// Internal: First invocation derives capacity; circular queue with head/tail; R_TRIG for edges

FUNCTION_BLOCK FB_FIFOQueue
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
    R_Trig_Reset   : R_TRIG;
    R_Trig_Enqueue : R_TRIG;
    R_Trig_Dequeue : R_TRIG;
    head           : DINT := 0;
    tail           : DINT := 0;
    count          : DINT := 0;
    capacity       : DINT := 0;
    tmp_Item       : DINT;
    tmp_Index      : DINT;
    tmp_FirstScan  : BOOL := TRUE;
END_VAR

(* CONTRACT_RULES [] *)

IF tmp_FirstScan THEN
    tmp_FirstScan := FALSE;
    tmp_Index := UPPER_BOUND(buffer, 1) - LOWER_BOUND(buffer, 1);
    capacity := DINT_TO_INT(tmp_Index) + 1;
    head := 0;
    tail := 0;
    count := 0;
END_IF

R_Trig_Reset(CLK := reset);
R_Trig_Enqueue(CLK := enqueue);
R_Trig_Dequeue(CLK := dequeue);

IF R_Trig_Reset.Q THEN
    count := 0;
    head := 0;
    tail := 0;
    elementCount := 0;
    status := 16#0000;
    RETURN;
END_IF

IF R_Trig_Enqueue.Q THEN
    IF count >= capacity THEN
        status := 16#8002;
        RETURN;
    END_IF
    tmp_Item := VARIANT_TO_DINT(item);
    tmp_Index := LOWER_BOUND(buffer, 1) + tail;
    buffer[tmp_Index] := DINT_TO_VARIANT(tmp_Item);
    tail := (tail + 1) MOD capacity;
    count := count + 1;
    elementCount := count;
    status := 16#0000;
    RETURN;
END_IF

IF R_Trig_Dequeue.Q THEN
    IF count <= 0 THEN
        status := 16#8001;
        RETURN;
    END_IF
    tmp_Index := LOWER_BOUND(buffer, 1) + head;
    tmp_Item := VARIANT_TO_DINT(buffer[tmp_Index]);
    item := DINT_TO_VARIANT(tmp_Item);
    head := (head + 1) MOD capacity;
    count := count - 1;
    elementCount := count;
    status := 16#0000;
    RETURN;
END_IF

elementCount := count;
status := 16#0000;

END_FUNCTION_BLOCK
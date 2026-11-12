FUNCTION_BLOCK FB
(* ENGINEERING_CONTRACT:
   - Outputs: elementCount (retention, no explicit reset, DINT), status (idle/result, WORD)
   - Input behaviors: enqueue/dequeue are rising-edge; reset is level-triggered (highest priority)
   - PUB001: enqueue appends item to tail if queue not full (strict < capacity)
   - PUB002: dequeue reads head, writes to item, advances head if queue not empty (strict > 0)
   - PUB003: reset (TRUE) clears head=tail=lowerBound, elementCount=0; no buffer overwrite
   - PUB004: elementCount reflects current valid elements, 0..capacity inclusive
   - PUB005: rejection returns item/queue unchanged, sets status
   - PUB006: status 16#0000=no error, 16#8001=dequeue empty, 16#8002=queue full
   - First invocation: empty queue, capacity derived from LOWER_BOUND/UPPER_BOUND
   - Head and tail wrap via MOD; reset takes priority over same-scan enqueue/dequeue
*)

TYPE ANY_ELEMENT : BYTE(0); END_TYPE

VAR_INPUT
    enqueue  : BOOL;
    dequeue  : BOOL;
    reset    : BOOL;
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
    enqueueTrig : R_TRIG;
    dequeueTrig : R_TRIG;
    head        : DINT;
    tail        : DINT;
    capacity    : DINT;
    lower       : DINT;
    firstRun    : BOOL := TRUE;
    local_item  : ANY_ELEMENT;
END_VAR

// (* CONTRACT_RULES [] *)

IF firstRun THEN
    firstRun := TRUE;
    lower    := LOWER_BOUND(buffer, 1);
    capacity := UPPER_BOUND(buffer, 1) - LOWER_BOUND(buffer, 1) + 1;
    head     := lower;
    tail     := lower;
    elementCount := 0;
    status   := 16#0000;
    firstRun := FALSE;
END_IF;

enqueueTrig(CLK := enqueue);
dequeueTrig(CLK := dequeue);

IF reset THEN
    head := lower;
    tail := lower;
    elementCount := 0;
    status := 16#0000;
ELSIF dequeueTrig.Q THEN
    IF elementCount = 0 THEN
        status := 16#8001;
    ELSE
        local_item := buffer[head];
        item := local_item;
        head := lower + ((head - lower + 1) MOD capacity);
        elementCount := elementCount - 1;
        status := 16#0000;
    END_IF;
ELSIF enqueueTrig.Q THEN
    IF elementCount >= capacity THEN
        status := 16#8002;
    ELSE
        local_item := item;
        buffer[tail] := local_item;
        tail := lower + ((tail - lower + 1) MOD capacity);
        elementCount := elementCount + 1;
        status := 16#0000;
    END_IF;
ELSE
    status := 16#0000;
END_IF;
END_FUNCTION_BLOCK
FUNCTION_BLOCK FB
(* ENGINEERING_CONTRACT:
   - Outputs: elementCount (retention, no explicit reset, DINT), status (idle/result, WORD)
   - Input behaviors: enqueue/dequeue are rising-edge; reset is level-triggered (highest priority)
   - PUB001: enqueue appends item to tail if queue not full (strict < capacity)
   - PUB002: dequeue reads head, writes to item, advances head if queue not empty (strict > 0)
   - PUB003: reset (TRUE) clears head=tail=0, elementCount=0; no buffer overwrite
   - PUB004: elementCount reflects current valid elements, 0..capacity inclusive
   - PUB005: rejection returns item/queue unchanged, sets status
   - PUB006: status 16#0000=no error, 16#8001=dequeue empty, 16#8002=queue full
   - First invocation: empty queue, capacity derived from __ARRAYSIZE(buffer)
   - Head and tail wrap via MOD; no same-scan rejection per spec (reset-first priority)
*)
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
    firstRun    : BOOL := TRUE;
END_VAR

// (* CONTRACT_RULES [] *)

IF firstRun THEN
    firstRun := FALSE;
    capacity := __ARRAYSIZE(buffer);
    head := 0;
    tail := 0;
    elementCount := 0;
    status := 16#0000;
END_IF

enqueueTrig(CLK := enqueue);
dequeueTrig(CLK := dequeue);

IF reset THEN
    head := 0;
    tail := 0;
    elementCount := 0;
    status := 16#0000;
ELSIF dequeueTrig.Q THEN
    IF elementCount = 0 THEN
        status := 16#8001;
    ELSE
        item := __GETARRAYELEM(buffer, head + 1);
        head := (head + 1) MOD capacity;
        elementCount := elementCount - 1;
        status := 16#0000;
    END_IF;
ELSIF enqueueTrig.Q THEN
    IF elementCount >= capacity THEN
        status := 16#8002;
    ELSE
        __SETARRAYELEM(buffer, tail + 1, item);
        tail := (tail + 1) MOD capacity;
        elementCount := elementCount + 1;
        status := 16#0000;
    END_IF;
ELSE
    status := 16#0000;
END_IF;
END_FUNCTION_BLOCK
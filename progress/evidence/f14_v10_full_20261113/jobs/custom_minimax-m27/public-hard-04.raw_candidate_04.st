FUNCTION_BLOCK FB
(* ENGINEERING_CONTRACT:
   - Outputs: elementCount (retention, no explicit reset, DINT 0..capacity),
              status (WORD: 16#0000 idle/OK, 16#8001 empty reject, 16#8002 full reject)
   - Input edge behavior: enqueue/dequeue require R_TRIG rising edge per PUB001/PUB002
   - PUB003 reset priority: level-triggered, clears head=tail=0, elementCount=0
   - PUB004 elementCount: strict DINT range 0..capacity, reflects valid elements only
   - PUB005 rejection: queue and item unchanged, status encodes reason
   - First invocation: firstRun initializes head=tail=0, capacity=actual array length
   - Same-scan priority: reset > dequeue > enqueue; no simultaneous add+remove
   - MOD wraps head/tail; __GETAT/__SETAT use 1-based indices per CODESYS convention
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
END_IF;

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
        item := __GETAT(buffer, head + 1);
        head := (head + 1) MOD capacity;
        elementCount := elementCount - 1;
        status := 16#0000;
    END_IF;
ELSIF enqueueTrig.Q THEN
    IF elementCount >= capacity THEN
        status := 16#8002;
    ELSE
        __SETAT(buffer, tail + 1, item);
        tail := (tail + 1) MOD capacity;
        elementCount := elementCount + 1;
        status := 16#0000;
    END_IF;
ELSE
    status := 16#0000;
END_IF;
END_FUNCTION_BLOCK
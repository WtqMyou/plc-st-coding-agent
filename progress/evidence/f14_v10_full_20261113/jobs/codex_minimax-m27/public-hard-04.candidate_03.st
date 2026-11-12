(* CONTRACT_RULES [] *)
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
    local_head        : DINT  := 0;
    local_tail        : DINT  := 0;
    local_capacity    : DINT  := 0;
    local_firstCycle  : BOOL  := TRUE;
    local_enqueueTrig : R_TRIG;
    local_dequeueTrig : R_TRIG;
END_VAR

// ENGINEERING_CONTRACT
// =============================================================================
// PUB001: Capacity derived from buffer array length; element type from array.
// PUB002: Enqueue on rising edge, append if not full; tail advances circularly.
// PUB003: Dequeue on rising edge, retrieve front if not empty; head advances.
// PUB004: Reset clears queue; takes priority; buffer values need not be cleared.
// PUB005: elementCount [0..capacity] reports valid elements; zero = empty.
// PUB006: Status 16#0000 idle/success, 16#8001 empty-dequeue, 16#8002 full-enqueue.
// PUB007: Caller must not enqueue and dequeue same scan; no interlock enforced.
// PUB008: Queue empty on first invocation; firstCycle init on first call.
// PUB009-PUB011: Status codes as defined.
// Activation: R_TRIG on enqueue/dequeue; state persists across scans.
// Retention: head, tail, elementCount held; reset clears them.
// Reset priority: reset > enqueue > dequeue > idle; one operation per scan.
// Boundaries: Capacity from LOWER/UPPER_BOUND; indices MOD capacity.
// =============================================================================

// Rising-edge detection
local_enqueueTrig(CLK := enqueue);
local_dequeueTrig(CLK := dequeue);

// First invocation: derive capacity from buffer array bounds
IF local_firstCycle THEN
    local_firstCycle := FALSE;
    local_capacity := TO_DINT(UPPER_BOUND(buffer, 1) - LOWER_BOUND(buffer, 1) + 1);
    local_head := 0;
    local_tail := 0;
    elementCount := 0;
    status := 16#0000;
    RETURN;
END_IF;

// Reset: highest priority
IF reset THEN
    local_head := 0;
    local_tail := 0;
    elementCount := 0;
    status := 16#0000;
    RETURN;
END_IF;

// Enqueue request
IF local_enqueueTrig.Q THEN
    IF elementCount < local_capacity THEN
        buffer[local_tail] := item;
        local_tail := (local_tail + 1) MOD local_capacity;
        elementCount := elementCount + 1;
        status := 16#0000;
    ELSE
        status := 16#8002;
    END_IF;
    RETURN;
END_IF;

// Dequeue request
IF local_dequeueTrig.Q THEN
    IF elementCount > 0 THEN
        item := buffer[local_head];
        local_head := (local_head + 1) MOD local_capacity;
        elementCount := elementCount - 1;
        status := 16#0000;
    ELSE
        status := 16#8001;
    END_IF;
    RETURN;
END_IF;

// Idle scan
status := 16#0000;
END_FUNCTION_BLOCK
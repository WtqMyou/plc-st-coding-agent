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
    local_head         : DINT  := 0;
    local_tail         : DINT  := 0;
    local_capacity     : DINT  := 0;
    local_firstCycle   : BOOL  := TRUE;
    local_enqueueTrig  : R_TRIG;
    local_dequeueTrig  : R_TRIG;
END_VAR

// ENGINEERING_CONTRACT
// =============================================================================
// Activation: R_TRIG on enqueue/dequeue detect rising edges only.
// Retention:  local_head, local_tail, elementCount persist across scans.
// Reset:      Any scan where reset=TRUE empties queue regardless of other inputs.
// Same-scan:  Reset > Enqueue > Dequeue priority chain; only one operation per scan.
// Boundaries: Capacity derived from buffer array bounds; elementCount [0..capacity].
// Status:     16#0000 idle/success, 16#8001 empty-dequeue, 16#8002 full-enqueue.
// =============================================================================

// Rising-edge detection on command inputs
local_enqueueTrig(CLK := enqueue);
local_dequeueTrig(CLK := dequeue);

// First invocation: initialize capacity from buffer array bounds
IF local_firstCycle THEN
    local_firstCycle := FALSE;
    local_capacity := TO_DINT(UPPER_BOUND(buffer, 1) - LOWER_BOUND(buffer, 1) + 1);
    local_head := 0;
    local_tail := 0;
    elementCount := 0;
    status := 16#0000;
    RETURN;
END_IF;

// Reset: priority over enqueue/dequeue
IF reset THEN
    local_head := 0;
    local_tail := 0;
    elementCount := 0;
    status := 16#0000;
    RETURN;
END_IF;

// Enqueue request: rising edge + not full
IF local_enqueueTrig.Q THEN
    IF elementCount < local_capacity THEN
        // Append item at tail position
        buffer[local_tail] := item;
        local_tail := (local_tail + 1) MOD local_capacity;
        elementCount := elementCount + 1;
        status := 16#0000;
    ELSE
        status := 16#8002; // Full rejection
    END_IF;
    RETURN;
END_IF;

// Dequeue request: rising edge + not empty
IF local_dequeueTrig.Q THEN
    IF elementCount > 0 THEN
        // Retrieve and remove front element
        item := buffer[local_head];
        local_head := (local_head + 1) MOD local_capacity;
        elementCount := elementCount - 1;
        status := 16#0000;
    ELSE
        status := 16#8001; // Empty rejection
    END_IF;
    RETURN;
END_IF;

// Idle scan: no pending operation
status := 16#0000;
END_FUNCTION_BLOCK
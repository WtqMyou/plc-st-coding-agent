(*
ENGINEERING_CONTRACT
1. elementCount: stored queue count; initial 0; reset->0; enqueue +1 on success;
   dequeue -1 on success; retained otherwise; range 0..capacity (PUB004).
2. status: per-scan combinational; default 16#0000 every invocation; set 16#8001 only
   for empty dequeue and 16#8002 only for full enqueue (PUB005). Reset clears to 0 (PUB003).
3. queue state head/tail/count initialized from buffer bounds on first call;
   capacity = UPPER_BOUND-LOWER_BOUND+1; empty first call (PUB006).
4. enqueue/dequeue edge-triggered via R_TRIG; one request per rising edge;
   reset TRUE consumes/ignores all edges and has priority (PUB001,PUB002,PUB003).
5. enqueue reads item and writes buffer[tail] only when count<capacity.
   dequeue writes item from buffer[head] only when count>0; rejected requests leave item and buffer unchanged (PUB005).
6. VARIANT buffer/output: direct indexed copy with matching element type;
   buffer bounds and association fixed per instance (PUB001,PUB006).
7. Simultaneous enqueue and dequeue is prohibited by caller (PUB002);
   implementation processes dequeue then enqueue if violated.
8. Units: elementCount elements; status WORD exact codes; buffer indices follow actual lower/upper bounds.
*)
(* CONTRACT_RULES [] *)
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
    item : VARIANT;
    buffer : VARIANT;
END_VAR
VAR
    local_enq_edge : R_TRIG;
    local_deq_edge : R_TRIG;
    local_enq_req : BOOL;
    local_deq_req : BOOL;
    local_initialized : BOOL;
    local_lower : DINT;
    local_upper : DINT;
    local_capacity : DINT;
    local_head : DINT;
    local_tail : DINT;
    local_count : DINT;
END_VAR

IF NOT local_initialized THEN
    local_lower := LOWER_BOUND(buffer, 1);
    local_upper := UPPER_BOUND(buffer, 1);
    local_capacity := local_upper - local_lower + 1;
    IF local_capacity < 0 THEN
        local_capacity := 0;
    END_IF;
    local_head := local_lower;
    local_tail := local_lower;
    local_count := 0;
    local_initialized := TRUE;
END_IF;

elementCount := local_count;
status := WORD#16#0000;

local_enq_edge(CLK := enqueue);
local_deq_edge(CLK := dequeue);
local_enq_req := local_enq_edge.Q;
local_deq_req := local_deq_edge.Q;

IF reset THEN
    local_count := 0;
    local_head := local_lower;
    local_tail := local_lower;
    elementCount := 0;
    status := WORD#16#0000;
ELSE
    IF local_deq_req THEN
        IF local_count <= 0 THEN
            status := WORD#16#8001;
        ELSE
            item := buffer[local_head];
            local_head := local_head + 1;
            IF local_head > local_upper THEN
                local_head := local_lower;
            END_IF;
            local_count := local_count - 1;
            status := WORD#16#0000;
        END_IF;
    END_IF;

    IF local_enq_req THEN
        IF local_count >= local_capacity THEN
            status := WORD#16#8002;
        ELSE
            buffer[local_tail] := item;
            local_tail := local_tail + 1;
            IF local_tail > local_upper THEN
                local_tail := local_lower;
            END_IF;
            local_count := local_count + 1;
            status := WORD#16#0000;
        END_IF;
    END_IF;
END_IF;

elementCount := local_count;
END_FUNCTION_BLOCK
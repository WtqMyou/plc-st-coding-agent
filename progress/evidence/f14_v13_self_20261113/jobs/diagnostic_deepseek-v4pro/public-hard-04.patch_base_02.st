(* ENGINEERING_CONTRACT
   elementCount DINT: retained process value; 0 after reset, +1 successful enqueue, -1 successful dequeue, held otherwise; range 0..capacity.
   status WORD: overwritten every invocation; 0 idle/reset/success, 16#8002 rejected full enqueue, 16#8001 rejected empty dequeue; reset priority sets 0.
   queue state: first invocation empty; reset priority clears head/tail/count; enqueue writes at tail, dequeue reads head; circular indices low..high.
   edge triggers: R_TRIG consumed every scan; reset priority ignores edge requests; simultaneous enqueue+dequeue unspecified -> no-op.
   units/boundaries: capacity positive DINT derived each scan from LOWER_BOUND/UPPER_BOUND of the supplied array; first element index may be nonzero.
*)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FIFO
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
    local_rEnq : R_TRIG;
    local_rDeq : R_TRIG;
    local_enqEdge : BOOL;
    local_deqEdge : BOOL;

    local_low : DINT;
    local_high : DINT;
    local_capacity : DINT;
    local_count : DINT := 0;
    local_head : DINT := 0;
    local_tail : DINT := 0;
END_VAR

local_rEnq(CLK := enqueue);
local_enqEdge := local_rEnq.Q;
local_rDeq(CLK := dequeue);
local_deqEdge := local_rDeq.Q;

status := 16#0000;

local_low := LOWER_BOUND(buffer, 1);
local_high := UPPER_BOUND(buffer, 1);
local_capacity := local_high - local_low + 1;
IF local_capacity < 1 THEN
    local_capacity := 1;
END_IF;

IF local_count = 0 THEN
    local_head := local_low;
    local_tail := local_low;
END_IF;

IF reset THEN
    local_count := 0;
    local_head := local_low;
    local_tail := local_low;
    status := 16#0000;
ELSE
    IF local_enqEdge AND NOT local_deqEdge THEN
        IF local_count < local_capacity THEN
            buffer[local_tail] := item;
            local_tail := local_tail + 1;
            IF local_tail > local_high THEN
                local_tail := local_low;
            END_IF;
            local_count := local_count + 1;
            status := 16#0000;
        ELSE
            status := 16#8002;
        END_IF;
    ELSIF local_deqEdge AND NOT local_enqEdge THEN
        IF local_count > 0 THEN
            item := buffer[local_head];
            local_head := local_head + 1;
            IF local_head > local_high THEN
                local_head := local_low;
            END_IF;
            local_count := local_count - 1;
            status := 16#0000;
        ELSE
            status := 16#8001;
        END_IF;
    END_IF;
END_IF;

elementCount := local_count;

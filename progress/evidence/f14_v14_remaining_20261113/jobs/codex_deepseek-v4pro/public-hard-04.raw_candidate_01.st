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
    tmp_enq_rise : R_TRIG;
    tmp_deq_rise : R_TRIG;
    tmp_enq_edge : BOOL;
    tmp_deq_edge : BOOL;
    tmp_lower : DINT;
    tmp_upper : DINT;
    tmp_capacity : DINT;
    tmp_head : DINT;
    tmp_tail : DINT;
    tmp_initialized : BOOL := FALSE;
END_VAR

(* ENGINEERING_CONTRACT
- elementCount: initialized to 0 on first invocation; incremented only after successful enqueue; decremented only after successful dequeue; set to 0 by reset.
- enqueue: rising edge appends item at tail and advances tail while elementCount < capacity; on full queue rejects with 16#8002 and leaves item unchanged (PUB001,PUB004,PUB005,PUB009).
- dequeue: rising edge writes buffer[head] back to item and advances head while elementCount > 0; on empty queue rejects with 16#8001 and leaves item unchanged (PUB002,PUB004,PUB005,PUB008).
- reset: TRUE empties the queue, sets elementCount to 0, and resets head/tail; reset has priority over enqueue/dequeue (PUB003).
- capacity: stored on first invocation as UPPER_BOUND(buffer,1)-LOWER_BOUND(buffer,1)+1; full means count equals capacity (PUB004,PUB010).
- status: reset to 16#0000 each invocation; rejection codes override no-error status (PUB006,PUB008,PUB009).
- enqueue+dequeue in the same invocation is caller-forbidden; implementation processes enqueue before dequeue for a deterministic forbidden-input result (PUB002).
*)

(* CONTRACT_RULES [] *)

tmp_enq_rise(CLK := enqueue);
tmp_deq_rise(CLK := dequeue);
tmp_enq_edge := tmp_enq_rise.Q;
tmp_deq_edge := tmp_deq_rise.Q;

IF NOT tmp_initialized THEN
    tmp_lower := TO_DINT(LOWER_BOUND(buffer, 1));
    tmp_upper := TO_DINT(UPPER_BOUND(buffer, 1));
    tmp_capacity := tmp_upper - tmp_lower + 1;
    tmp_head := tmp_lower;
    tmp_tail := tmp_lower;
    elementCount := 0;
    tmp_initialized := TRUE;
END_IF;

status := 16#0000;

IF reset THEN
    elementCount := 0;
    tmp_head := tmp_lower;
    tmp_tail := tmp_lower;
ELSE
    IF tmp_enq_edge THEN
        IF elementCount >= tmp_capacity THEN
            status := 16#8002;
        ELSE
            buffer[tmp_tail] := item;
            elementCount := elementCount + 1;
            tmp_tail := tmp_tail + 1;
            IF tmp_tail > tmp_upper THEN
                tmp_tail := tmp_lower;
            END_IF;
        END_IF;
    END_IF;

    IF tmp_deq_edge THEN
        IF elementCount <= 0 THEN
            status := 16#8001;
        ELSE
            item := buffer[tmp_head];
            elementCount := elementCount - 1;
            tmp_head := tmp_head + 1;
            IF tmp_head > tmp_upper THEN
                tmp_head := tmp_lower;
            END_IF;
        END_IF;
    END_IF;
END_IF;

END_FUNCTION_BLOCK
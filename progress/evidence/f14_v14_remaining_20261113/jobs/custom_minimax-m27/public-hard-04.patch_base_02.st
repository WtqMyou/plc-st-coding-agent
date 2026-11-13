FUNCTION_BLOCK FB
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
    head          : DINT := 0;
    tail          : DINT := 0;
    enqueue_prev  : BOOL := FALSE;
    dequeue_prev  : BOOL := FALSE;
    enqueue_trig  : R_TRIG;
    dequeue_trig  : R_TRIG;
    tmp_lower     : DINT;
    tmp_upper     : DINT;
    tmp_capacity  : DINT;
    tmp_element   : DINT;
END_VAR
VAR_TEMP
    emptyArray : ARRAY[0..0] OF DINT;
END_VAR
// ENGINEERING_CONTRACT
// ─────────────────────────────────────────────────────────────────────────────
// PUB001: enqueue rising edge → write item to tail; reject if elementCount == capacity.
// PUB002: dequeue rising edge → read buffer[head] to item; reject if elementCount == 0.
// PUB003: reset TRUE → head:=0, tail:=0, elementCount:=0; no buffer overwrite.
// PUB004: elementCount output tracks live queue size (0..capacity).
// PUB005: status 16#0000=no error/idle; 16#8001=dequeue reject (empty);
//         16#8002=enqueue reject (full); 16#8003=simultaneous enqueue+dequeue.
// PUB006: buffer is caller-supplied VARIANT array; capacity = UPPER-LOWER+1.
// PUB007: item is VARIANT scalar; type must match buffer element type.
// PUB008: circular queue uses head (read index) and tail (write index) modulo capacity.
// PUB009: first invocation initializes to empty state (no prior buffer content used).
// PUB010: reset has priority over enqueue/dequeue.
// PUB011: simultaneous enqueue+dequeue is invalid usage → rejected with status 16#8003.
// ─────────────────────────────────────────────────────────────────────────────
// (* CONTRACT_RULES [] *)
// ─────────────────────────────────────────────────────────────────────────────
    // Capture rising edges for enqueue and dequeue commands
    enqueue_trig(CLK := enqueue);
    dequeue_trig(CLK := dequeue);
    
    // Update previous state for next scan edge detection
    enqueue_prev  := enqueue;
    dequeue_prev  := dequeue;
    
    // Reject simultaneous enqueue and dequeue requests
    IF enqueue AND dequeue THEN
        status := 16#8003;
        RETURN;
    END_IF;
    
    // Validate buffer pointer and extract array bounds
    IF __ISVALIDPTR(buffer, TO_DINT(SIZEOF(emptyArray))) THEN
        tmp_lower    := LOWER_BOUND(buffer, 1);
        tmp_upper    := UPPER_BOUND(buffer, 1);
        tmp_capacity := TO_DINT(tmp_upper - tmp_lower + 1);
        
        // Validate capacity is positive
        IF tmp_capacity <= 0 THEN
            status := 16#FFFF;
            RETURN;
        END_IF;
        
        // Type validation: ensure item type matches buffer element type
        // by reading from buffer then assigning to item (runtime type check)
        tmp_element := buffer[tmp_lower];
        tmp_element := item;
        
        // Execute prioritized operations
        IF reset THEN
            // PUB003: Reset clears queue state without overwriting buffer content
            head        := 0;
            tail        := 0;
            elementCount := 0;
            status      := 16#0000;
        ELSIF enqueue_trig.Q THEN
            // PUB001: Enqueue operation
            IF elementCount >= tmp_capacity THEN
                // Queue full - reject enqueue
                status := 16#8002;
            ELSE
                // Write item to tail position, advance tail circularly
                buffer[tail] := item;
                tail         := (tail + 1) MOD tmp_capacity;
                elementCount := elementCount + 1;
                status       := 16#0000;
            END_IF;
        ELSIF dequeue_trig.Q THEN
            // PUB002: Dequeue operation
            IF elementCount <= 0 THEN
                // Queue empty - reject dequeue
                status := 16#8001;
            ELSE
                // Read from head position, advance head circularly
                item        := buffer[head];
                head        := (head + 1) MOD tmp_capacity;
                elementCount := elementCount - 1;
                status       := 16#0000;
            END_IF;
        ELSE
            // No operation requested this scan
            status := 16#0000;
        END_IF;
    ELSE
        status := 16#FFFF;
    END_IF;
END_FUNCTION_BLOCK
FUNCTION_BLOCK FB_FIFO
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
    localCapacity : DINT;
    localLower : DINT;
    localHead : DINT;
    localTail : DINT;
    localCount : DINT;
    localNext : DINT;
    localLastEnqueue : BOOL;
    localLastDequeue : BOOL;
    localRisingEnqueue : BOOL;
    localRisingDequeue : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
   validCount: activated by successful enqueue/dequeue; reset to 0 by reset (PUB001/PUB003).
   elementCount: mirror of persistent validCount each scan; reset sets it to 0 (PUB003/PUB004).
   status: default 16#0000; 16#8001 empty dequeue reject; 16#8002 full enqueue reject (PUB005).
   head/tail: internal only, initialized to buffer lower bound, advanced circularly (PUB006).
   priority: reset is processed before all queue operations (PUB003).
   same scan: caller precondition forbids simultaneous edges; if both occur enqueue is handled first (PUB002).
   full condition: validCount = capacity; empty condition: validCount = 0 (PUB004).
   capacity: UPPER_BOUND(buffer,1)-LOWER_BOUND(buffer,1)+1; indices are DINT (PUB004/PUB006).
   rejected operations: item and queue are not modified (PUB005).
   units/bounds: elementCount DINT 0..capacity; status WORD; no unconditional public BOOL latch.
*)

(* CONTRACT_RULES [] *)

IF localCapacity = 0 THEN
    localLower := LOWER_BOUND(buffer, 1);
    localCapacity := UPPER_BOUND(buffer, 1) - localLower + 1;
    localHead := localLower;
    localTail := localLower;
    localCount := 0;
END_IF;

status := WORD#16#0000;

localRisingEnqueue := enqueue AND NOT localLastEnqueue;
localRisingDequeue := dequeue AND NOT localLastDequeue;

IF reset THEN
    localCount := 0;
    localHead := localLower;
    localTail := localLower;
ELSE
    IF localRisingEnqueue THEN
        IF localCount < localCapacity THEN
            buffer[localTail] := item;
            localNext := localTail - localLower + 1;
            IF localNext >= localCapacity THEN
                localNext := 0;
            END_IF;
            localTail := localLower + localNext;
            localCount := localCount + 1;
        ELSE
            status := WORD#16#8002;
        END_IF;
    END_IF;

    IF localRisingDequeue THEN
        IF localCount > 0 THEN
            item := buffer[localHead];
            localNext := localHead - localLower + 1;
            IF localNext >= localCapacity THEN
                localNext := 0;
            END_IF;
            localHead := localLower + localNext;
            localCount := localCount - 1;
        ELSE
            status := WORD#16#8001;
        END_IF;
    END_IF;
END_IF;

elementCount := localCount;

localLastEnqueue := enqueue;
localLastDequeue := dequeue;

END_FUNCTION_BLOCK
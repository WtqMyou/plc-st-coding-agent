(* --------------------------------------------------
   FUNCTION BLOCK FIFO
   First‑In‑First‑Out circular queue using the caller‑supplied buffer.
   Derives capacity and element type from the buffer.
   -------------------------------------------------- *)
FUNCTION_BLOCK FIFO
VAR_INPUT
    enqueue  : BOOL;      (* Rising edge → enqueue one item           *)
    dequeue  : BOOL;      (* Rising edge → dequeue one item           *)
    reset    : BOOL;      (* TRUE → empty the queue, highest priority *)
END_VAR
VAR_OUTPUT
    elementCount : DINT;  (* Number of valid elements (0 … capacity) *)
    status       : WORD;  (* 16#0000, 16#8001, 16#8002                *)
END_VAR
VAR_IN_OUT
    item   : VARIANT;     (* Scalar to read (enqueue) or write (dequeue) *)
    buffer : VARIANT;     (* One‑dimensional array used as storage       *)
END_VAR

VAR
    (* Internal queue state --------------------------------------------------- *)
    headIndex   : DINT;   (* Current head position (real array index)        *)
    tailIndex   : DINT;   (* Current tail position (real array index)        *)
    count       : DINT;   (* Number of stored elements (mirrors elementCount) *)

    (* Array bounds (re‑computed each cycle because buffer never changes) ----- *)
    lowerBound  : DINT;   (* LOWER_BOUND(buffer,1)                           *)
    upperBound  : DINT;   (* UPPER_BOUND(buffer,1)                           *)
    capacity    : DINT;   (* upperBound - lowerBound + 1                     *)

    (* Edge detection --------------------------------------------------------- *)
    prevEnqueue : BOOL;   (* Value of enqueue from previous cycle            *)
    prevDequeue : BOOL;   (* Value of dequeue from previous cycle            *)
    enqueueRising : BOOL; (* TRUE on a rising edge of enqueue                *)
    dequeueRising : BOOL; (* TRUE on a rising edge of dequeue                *)

    (* First‑call initialization ---------------------------------------------- *)
    initDone    : BOOL;   (* TRUE after the first execution                  *)
END_VAR

(* -------------------------------------------------------------------------- *)
(* Body of the function block                                                 *)
(* -------------------------------------------------------------------------- *)

(* 1. Determine capacity from the supplied buffer ----------------------------- *)
lowerBound := LOWER_BOUND(buffer, 1);
upperBound := UPPER_BOUND(buffer, 1);
capacity   := upperBound - lowerBound + 1;

(* 2. Initialise internal variables on the very first call ------------------- *)
IF NOT initDone THEN
    headIndex := lowerBound;
    tailIndex := lowerBound;
    count     := 0;
    initDone  := TRUE;
END_IF

(* 3. Reset handling (highest priority) ------------------------------------- *)
IF reset THEN
    count     := 0;
    headIndex := lowerBound;
    tailIndex := lowerBound;
    status    := 16#0000;                     (* no error                     *)
ELSE
    (* 4. Detect rising edges on enqueue / dequeue --------------------------- *)
    enqueueRising := enqueue AND NOT prevEnqueue;
    dequeueRising := dequeue AND NOT prevDequeue;

    (* Store current input states for next cycle ----------------------------- *)
    prevEnqueue := enqueue;
    prevDequeue := dequeue;

    (* Default status = no error -------------------------------------------- *)
    status := 16#0000;

    (* 5. Enqueue request ----------------------------------------------------- *)
    IF enqueueRising THEN
        IF count < capacity THEN
            (* Append the current item to the tail -------------------------- *)
            buffer[tailIndex] := item;

            (* Advance tail (circular) -------------------------------------- *)
            tailIndex := tailIndex + 1;
            IF tailIndex > upperBound THEN
                tailIndex := lowerBound;
            END_IF

            count := count + 1;
        ELSE
            (* Queue full – reject the request -------------------------------- *)
            status := 16#8002;
        END_IF
    END_IF

    (* 6. Dequeue request ----------------------------------------------------- *)
    IF dequeueRising THEN
        IF count > 0 THEN
            (* Copy the front element to item -------------------------------- *)
            item := buffer[headIndex];

            (* Advance head (circular) --------------------------------------- *)
            headIndex := headIndex + 1;
            IF headIndex > upperBound THEN
                headIndex := lowerBound;
            END_IF

            count := count - 1;
        ELSE
            (* Queue empty – reject the request ------------------------------- *)
            status := 16#8001;
        END_IF
    END_IF
END_IF

(* 7. Publish the current number of stored elements -------------------------- *)
elementCount := count;

END_FUNCTION_BLOCK
FUNCTION_BLOCK FB_FIFO_Queue
VAR_INPUT
    enqueue   : BOOL;  (* Rising edge requests one enqueue *)
    dequeue   : BOOL;  (* Rising edge requests one dequeue *)
    reset     : BOOL;  (* TRUE resets queue to empty *)
END_VAR
VAR_OUTPUT
    elementCount : DINT;  (* Current number of valid elements *)
    status       : WORD;  (* Invocation status *)
END_VAR
VAR_IN_OUT
    item   : VARIANT;  (* Mutable scalar reference *)
    buffer : VARIANT;  (* Reference to non-empty 1-D array *)
END_VAR
VAR
    initialized : BOOL := FALSE;

    lastEnqueue : BOOL := FALSE;
    lastDequeue : BOOL := FALSE;

    enqueueRise : BOOL;
    dequeueRise : BOOL;

    head     : DINT := 0;
    tail     : DINT := 0;
    count    : DINT := 0;
    capacity : DINT := 0;
    
    elementSize : DINT := 0;
    pBuffer     : POINTER TO BYTE;
    pItem       : POINTER TO BYTE;
    infoValid   : BOOL;
END_VAR

(*
    This implementation assumes the availability of the following
    runtime-library functions for VARIANT handling:

      VariantGetInfo(variant, pValue, elementSize, arrayLength)
      VariantSetElement(variant, index, value)
      VariantGetElement(variant, index, value)

    These functions are typically provided by the CODESYS/TwinCAT
    VariantAccess or IecVarAccess library.
*)

-----------------------------------------------------------
-- Initialisation: derive capacity and element type once
-----------------------------------------------------------
IF NOT initialized THEN
    infoValid := VariantGetInfo(variant := buffer,
                                pValue => pBuffer,
                                elementSize => elementSize,
                                arrayLength => capacity);

    IF NOT infoValid THEN
        capacity := 0;
        elementSize := 0;
    END_IF

    head := 0;
    tail := 0;
    count := 0;

    initialized := TRUE;
END_IF

-----------------------------------------------------------
-- Edge detection
-----------------------------------------------------------
enqueueRise := enqueue AND NOT lastEnqueue;
dequeueRise := dequeue AND NOT lastDequeue;

lastEnqueue := enqueue;
lastDequeue := dequeue;

-----------------------------------------------------------
-- Main operation
-----------------------------------------------------------
IF reset THEN
    (* Reset takes priority over enqueue and dequeue *)
    head := 0;
    tail := 0;
    count := 0;
    status := 16#0000;

ELSIF enqueueRise AND dequeueRise THEN
    (* Caller must not request both at the same time. *)
    (* Treat as no operation. *)
    status := 16#0000;

ELSIF enqueueRise THEN
    IF count < capacity THEN
        (* Append item to tail *)
        VariantSetElement(variant := buffer,
                          index := tail,
                          value := item);

        tail := (tail + 1) MOD capacity;
        count := count + 1;
        status := 16#0000;
    ELSE
        (* Queue full: reject enqueue, leave queue unchanged *)
        status := 16#8002;
    END_IF

ELSIF dequeueRise THEN
    IF count > 0 THEN
        (* Remove front element and write it to item *)
        VariantGetElement(variant := buffer,
                          index := head,
                          value := item);

        head := (head + 1) MOD capacity;
        count := count - 1;
        status := 16#0000;
    ELSE
        (* Queue empty: reject dequeue, leave item unchanged *)
        status := 16#8001;
    END_IF

ELSE
    (* Idle invocation – no error *)
    status := 16#0000;
END_IF

-----------------------------------------------------------
-- Update output
-----------------------------------------------------------
elementCount := count;

END_FUNCTION_BLOCK
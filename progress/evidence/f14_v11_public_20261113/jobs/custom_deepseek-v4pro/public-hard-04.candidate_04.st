(* ENGINEERING_CONTRACT
   elementCount DINT: retained process value; 0 after reset, +1 successful enqueue, -1 successful dequeue, held otherwise; range 0..capacity.
   status WORD: overwritten every invocation; 0 idle/reset/success, 16#8002 rejected full enqueue, 16#8001 rejected empty dequeue; reset priority sets 0.
   queue state: first invocation empty; reset priority clears head/tail/count; enqueue writes at tail, dequeue reads head; indices 0..capacity-1.
   edge triggers: R_TRIG consumed every scan; reset priority ignores edge requests; simultaneous enqueue+dequeue unspecified -> no-op.
   units/boundaries: capacity positive DINT derived once from buffer size / item element size; element copied byte-wise from item address.
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

    local_associated : BOOL := FALSE;
    local_pBufferBase : POINTER TO BYTE;
    local_pItemBase : POINTER TO BYTE;
    local_elemSize : DINT := 1;
    local_capacity : DINT := 1;

    local_count : DINT := 0;
    local_head : DINT := 0;
    local_tail : DINT := 0;

    local_bufInfo : __SYSTEM.VAR_INFO;
    local_itemInfo : __SYSTEM.VAR_INFO;

    local_pSrc : POINTER TO BYTE;
    local_pDst : POINTER TO BYTE;
    local_offset : DINT;
    local_copiedBytes : UDINT;
END_VAR

(* Consume rising edges every scan so reset cannot create ghost operations later. *)
local_rEnq(CLK := enqueue);
local_enqEdge := local_rEnq.Q;
local_rDeq(CLK := dequeue);
local_deqEdge := local_rDeq.Q;

status := 16#0000;

(* One-time association of buffer and item storage, using the first invocation. *)
IF NOT local_associated THEN
    local_bufInfo := __VARINFO(buffer);
    local_itemInfo := __VARINFO(item);

    local_elemSize := local_itemInfo.diSize;
    IF local_elemSize <= 0 THEN
        local_elemSize := 1;
    END_IF;

    local_capacity := local_bufInfo.diSize / local_elemSize;
    IF local_capacity < 1 THEN
        local_capacity := 1;
    END_IF;

    local_pBufferBase := local_bufInfo.pvAddress;
    local_pItemBase := local_itemInfo.pvAddress;
    local_associated := TRUE;
END_IF;

IF reset THEN
    (* Reset has priority over all operations; stored values remain untouched. *)
    local_count := 0;
    local_head := 0;
    local_tail := 0;
    status := 16#0000;
ELSE
    IF local_enqEdge AND NOT local_deqEdge THEN
        IF local_count < local_capacity THEN
            (* Copy current item value into tail slot. *)
            local_pSrc := local_pItemBase;
            local_pDst := local_pBufferBase;
            local_offset := local_tail * local_elemSize;
            local_pDst := local_pDst + local_offset;
            local_copiedBytes := SysMemCpy(
                pbyDest := local_pDst,
                pbySource := local_pSrc,
                dwCount := TO_DWORD(local_elemSize)
            );

            local_tail := (local_tail + 1) MOD local_capacity;
            local_count := local_count + 1;
            status := 16#0000;
        ELSE
            status := 16#8002; (* enqueue rejected: full *)
        END_IF;
    ELSIF local_deqEdge AND NOT local_enqEdge THEN
        IF local_count > 0 THEN
            (* Copy head element back to item. *)
            local_pSrc := local_pBufferBase;
            local_offset := local_head * local_elemSize;
            local_pSrc := local_pSrc + local_offset;
            local_pDst := local_pItemBase;
            local_copiedBytes := SysMemCpy(
                pbyDest := local_pDst,
                pbySource := local_pSrc,
                dwCount := TO_DWORD(local_elemSize)
            );

            local_head := (local_head + 1) MOD local_capacity;
            local_count := local_count - 1;
            status := 16#0000;
        ELSE
            status := 16#8001; (* dequeue rejected: empty *)
        END_IF;
    END_IF;
END_IF;

elementCount := local_count;
END_FUNCTION_BLOCK
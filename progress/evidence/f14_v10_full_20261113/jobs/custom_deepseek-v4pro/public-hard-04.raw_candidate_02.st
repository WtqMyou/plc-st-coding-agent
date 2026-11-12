(* ENGINEERING_CONTRACT
  PUB001/PUB002: rising edges of enqueue/dequeue are detected by R_TRIG instances each scan.
  PUB003: reset TRUE clears count/head/tail and returns before processing enq/deq requests.
  PUB004: elementCount equals stored count, range 0..capacity; capacity from buffer array length.
  PUB005: rejected full enqueue sets status 16#8002; rejected empty dequeue sets status 16#8001.
  PUB006: first invocation initializes empty state; head/tail/count are internal only.
  PUB007-PUB011: VARIANT buffer/item are accessed via __VARINFO and raw byte copy.
  Unspecified: simultaneous enqueue+dequeue is processed dequeue first, then enqueue.
  Unspecified: invalid buffer metadata leaves the block uninitialized with status 16#0000.
*)
(* CONTRACT_RULES [] *)

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
    rtEnq : R_TRIG;
    rtDeq : R_TRIG;

    init : BOOL := FALSE;
    capacity : DINT := 0;
    count : DINT := 0;
    head : UDINT := 0;
    tail : UDINT := 0;

    elemSize : UDINT := 0;
    pBuf : POINTER TO BYTE;
    pItem : POINTER TO BYTE;

    infoBuf : __SYSTEM.VAR_INFO;
    infoItem : __SYSTEM.VAR_INFO;

    i : UDINT;
    pSrc : POINTER TO BYTE;
    pDst : POINTER TO BYTE;

    tmpEnq : BOOL;
    tmpDeq : BOOL;
END_VAR

rtEnq(CLK := enqueue);
rtDeq(CLK := dequeue);
tmpEnq := rtEnq.Q;
tmpDeq := rtDeq.Q;

elementCount := 0;
status := 16#0000;

IF NOT init THEN
    __VARINFO(ADR(buffer), ADR(infoBuf));
    __VARINFO(ADR(item), ADR(infoItem));
    
    IF infoBuf.udiArrayLength > 0 THEN
        capacity := TO_DINT(infoBuf.udiArrayLength);
        elemSize := infoItem.udiSize;
        IF elemSize = 0 THEN
            elemSize := 1;
        END_IF;
        pBuf := infoBuf.pbyData;
        pItem := infoItem.pbyData;
        head := 0;
        tail := 0;
        count := 0;
        init := TRUE;
    ELSE
        elementCount := 0;
        status := 16#0000;
        RETURN;
    END_IF;
END_IF;

IF reset THEN
    head := 0;
    tail := 0;
    count := 0;
    elementCount := 0;
    status := 16#0000;
    RETURN;
END_IF;

IF tmpDeq THEN
    IF count > 0 THEN
        pSrc := pBuf + (head * elemSize);
        pDst := pItem;
        FOR i := UDINT#0 TO elemSize - UDINT#1 DO
            pDst^ := pSrc^;
            pDst := pDst + 1;
            pSrc := pSrc + 1;
        END_FOR;
        head := (head + UDINT#1) MOD TO_UDINT(capacity);
        count := count - 1;
    ELSE
        status := 16#8001;
    END_IF;
END_IF;

IF tmpEnq THEN
    IF count < capacity THEN
        pDst := pBuf + (tail * elemSize);
        pSrc := pItem;
        FOR i := UDINT#0 TO elemSize - UDINT#1 DO
            pDst^ := pSrc^;
            pDst := pDst + 1;
            pSrc := pSrc + 1;
        END_FOR;
        tail := (tail + UDINT#1) MOD TO_UDINT(capacity);
        count := count + 1;
    ELSE
        IF status = 16#0000 THEN
            status := 16#8002;
        END_IF;
    END_IF;
END_IF;

elementCount := count;

END_FUNCTION_BLOCK
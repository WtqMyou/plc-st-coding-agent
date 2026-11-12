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
    head : DINT := 0;
    tail : DINT := 0;
    count : DINT := 0;
    capacity : DINT := 0;
    elemSize : DINT := 0;
    initialized : BOOL := FALSE;
    prevEnqueue : BOOL := FALSE;
    prevDequeue : BOOL := FALSE;
    enqEdge : BOOL;
    deqEdge : BOOL;
    bufferAddr : PVOID;
    itemAddr : PVOID;
    bufferSize : DINT;
    itemSize : DINT;
    destAddr : PVOID;
    srcAddr : PVOID;
    copyLen : UDINT;
END_VAR

status := 16#0000;

IF NOT initialized THEN
    bufferSize := __VARINFO(buffer).diSize;
    itemSize := __VARINFO(item).diSize;
    IF (bufferSize > 0) AND (itemSize > 0) THEN
        elemSize := itemSize;
        capacity := bufferSize / elemSize;
        bufferAddr := __VARINFO(buffer).pvAddress;
        itemAddr := __VARINFO(item).pvAddress;
        head := 0;
        tail := 0;
        count := 0;
        initialized := TRUE;
    ELSE
        elementCount := 0;
        RETURN;
    END_IF;
END_IF;

enqEdge := enqueue AND NOT prevEnqueue;
deqEdge := dequeue AND NOT prevDequeue;
prevEnqueue := enqueue;
prevDequeue := dequeue;

IF reset THEN
    head := 0;
    tail := 0;
    count := 0;
    elementCount := 0;
    status := 16#0000;
    RETURN;
END_IF;

IF enqEdge THEN
    IF count >= capacity THEN
        status := 16#8002;
    ELSE
        destAddr := bufferAddr + (tail * elemSize);
        srcAddr := itemAddr;
        copyLen := TO_UDINT(elemSize);
        SysMemCpy(destAddr, srcAddr, copyLen);
        tail := tail + 1;
        IF tail >= capacity THEN
            tail := 0;
        END_IF;
        count := count + 1;
        status := 16#0000;
    END_IF;
END_IF;

IF deqEdge THEN
    IF count = 0 THEN
        status := 16#8001;
    ELSE
        srcAddr := bufferAddr + (head * elemSize);
        destAddr := itemAddr;
        copyLen := TO_UDINT(elemSize);
        SysMemCpy(destAddr, srcAddr, copyLen);
        head := head + 1;
        IF head >= capacity THEN
            head := 0;
        END_IF;
        count := count - 1;
        status := 16#0000;
    END_IF;
END_IF;

elementCount := count;
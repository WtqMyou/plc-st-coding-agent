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
    firstCall : BOOL := TRUE;
    lastEnqueue : BOOL := FALSE;
    lastDequeue : BOOL := FALSE;
    enqueueReq : BOOL;
    dequeueReq : BOOL;
    head : DINT := 0;
    tail : DINT := 0;
    validCount : DINT := 0;
    capacity : DINT := 0;
    targetIndex : DINT;
    infoHandle : RTS_IEC_HANDLE := RTS_INVALID_HANDLE;
    elementVariant : VARIANT;
    dummyCount : DINT;
END_VAR

status := WORD#16#0000;
enqueueReq := enqueue AND NOT lastEnqueue;
dequeueReq := dequeue AND NOT lastDequeue;

IF firstCall THEN
    firstCall := FALSE;
    head := 0;
    tail := 0;
    validCount := 0;
    infoHandle := VInfoGetFirstIndex(pSymbol := buffer,
                                     nMaxFeatures := DWORD#4,
                                     fFactoryInfo := FALSE,
                                     cElements := capacity);
    IF infoHandle <> RTS_INVALID_HANDLE THEN
        VInfoRelease(infoHandle);
        infoHandle := RTS_INVALID_HANDLE;
    ELSE
        capacity := 0;
    END_IF;
END_IF;

IF reset THEN
    head := 0;
    tail := 0;
    validCount := 0;

ELSIF enqueueReq THEN
    IF validCount >= capacity THEN
        status := WORD#16#8002;
    ELSE
        targetIndex := tail;
        infoHandle := VInfoGetFirstIndex(pSymbol := buffer,
                                         nMaxFeatures := DWORD#4,
                                         fFactoryInfo := FALSE,
                                         cElements := dummyCount);
        IF infoHandle <> RTS_INVALID_HANDLE THEN
            IF VInfoGetNthElement(infoHandle, targetIndex, elementVariant) THEN
                VARCpy(pDst := elementVariant, pSrc := item);
                tail := (tail + 1) MOD capacity;
                validCount := validCount + 1;
            END_IF;
            VInfoRelease(infoHandle);
            infoHandle := RTS_INVALID_HANDLE;
        END_IF;
    END_IF;

ELSIF dequeueReq THEN
    IF validCount <= 0 THEN
        status := WORD#16#8001;
    ELSE
        targetIndex := head;
        infoHandle := VInfoGetFirstIndex(pSymbol := buffer,
                                         nMaxFeatures := DWORD#4,
                                         fFactoryInfo := FALSE,
                                         cElements := dummyCount);
        IF infoHandle <> RTS_INVALID_HANDLE THEN
            IF VInfoGetNthElement(infoHandle, targetIndex, elementVariant) THEN
                VARCpy(pDst := item, pSrc := elementVariant);
                head := (head + 1) MOD capacity;
                validCount := validCount - 1;
            END_IF;
            VInfoRelease(infoHandle);
            infoHandle := RTS_INVALID_HANDLE;
        END_IF;
    END_IF;
END_IF;

lastEnqueue := enqueue;
lastDequeue := dequeue;
elementCount := validCount;
END_FUNCTION_BLOCK
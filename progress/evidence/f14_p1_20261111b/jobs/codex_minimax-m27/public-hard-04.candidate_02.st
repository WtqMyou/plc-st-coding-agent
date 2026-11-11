FUNCTION_BLOCK FB_FIFO
VAR_INPUT
    enqueue : BOOL;
    dequeue : BOOL;
    reset   : BOOL;
END_VAR

VAR_OUTPUT
    elementCount : DINT;
    status       : WORD;
END_VAR

VAR_IN_OUT
    item   : VARIANT;
    buffer : VARIANT;
END_VAR

VAR
    _head         : DINT := 0;
    _tail         : DINT := 0;
    _elementCount : DINT := 0;
    _capacity     : DINT;
    _elementSize  : DINT;
    _prevEnqueue  : BOOL := FALSE;
    _prevDequeue  : BOOL := FALSE;
    _initialized  : BOOL := FALSE;
END_VAR

// Initialization
IF NOT _initialized THEN
    VAR
        bufType : REF_TO ANY;
        capacity : DINT;
    END_VAR
    
    bufType REF= buffer;
    
    IF __ISVALIDREF(bufType) THEN
        capacity := bufType.GetUpperBound(1) + 1;
        _capacity := capacity;
        _elementSize := bufType.GetSize() / _capacity;
        _initialized := TRUE;
    END_IF;
    
    elementCount := 0;
    status := 16#0000;
    RETURN;
END_IF;

// Reset handling (highest priority)
IF reset THEN
    _head := 0;
    _tail := 0;
    _elementCount := 0;
    elementCount := 0;
    status := 16#0000;
    _prevEnqueue := FALSE;
    _prevDequeue := FALSE;
    RETURN;
END_IF;

// Rising edge detection
VAR
    enqueueRising : BOOL;
    dequeueRising : BOOL;
END_VAR

enqueueRising := enqueue AND NOT _prevEnqueue;
dequeueRising := dequeue AND NOT _prevDequeue;

_prevEnqueue := enqueue;
_prevDequeue := dequeue;

// Dequeue request (rising edge, queue not empty)
IF dequeueRising AND _elementCount > 0 THEN
    VAR
        pSrc     : POINTER TO BYTE;
        pDest    : POINTER TO BYTE;
        srcAdr   : LWORD;
        destAdr  : LWORD;
        zeroBuf  : ARRAY[0..255] OF BYTE;
    END_VAR
    
    srcAdr := __GET_VAR_DATA_REF(buffer).ADR + (_head * _elementSize);
    destAdr := __GET_VAR_DATA_REF(item).ADR;
    
    MemMove(TO_PTR(srcAdr), TO_PTR(destAdr), _elementSize);
    
    MemSet(zeroBuf, 0, SIZEOF(zeroBuf));
    MemMove(zeroBuf, TO_PTR(srcAdr), _elementSize);
    
    _head := (_head + 1) MOD _capacity;
    _elementCount := _elementCount - 1;
    elementCount := _elementCount;
    status := 16#0000;
    
// Enqueue request (rising edge, queue not full)
ELSIF enqueueRising AND _elementCount < _capacity THEN
    VAR
        pDest   : POINTER TO BYTE;
        pSrc    : POINTER TO BYTE;
        destAdr : LWORD;
        srcAdr  : LWORD;
    END_VAR
    
    destAdr := __GET_VAR_DATA_REF(buffer).ADR + (_tail * _elementSize);
    srcAdr := __GET_VAR_DATA_REF(item).ADR;
    
    MemMove(TO_PTR(srcAdr), TO_PTR(destAdr), _elementSize);
    
    _tail := (_tail + 1) MOD _capacity;
    _elementCount := _elementCount + 1;
    elementCount := _elementCount;
    status := 16#0000;
    
// Dequeue rejected: empty queue
ELSIF dequeueRising AND _elementCount = 0 THEN
    status := 16#8001;
    
// Enqueue rejected: full queue
ELSIF enqueueRising AND _elementCount >= _capacity THEN
    status := 16#8002;
    
// Idle (no rising edge or other condition)
ELSE
    status := 16#0000;
END_IF;
END_FUNCTION_BLOCK
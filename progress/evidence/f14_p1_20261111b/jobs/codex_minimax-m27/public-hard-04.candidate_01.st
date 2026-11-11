METHOD GetBufferInfo : BOOL
VAR_INPUT
    buffer : VARIANT;
END_VAR
VAR_OUTPUT
    capacity    : DINT;
    elementSize : DINT;
END_VAR

VAR
    pBuffer    : REFERENCE TO BYTE;
    bufferType : REF_TO ANY;
END_VAR

bufferType REF= buffer;

IF __ISVALIDREF(bufferType) THEN
    capacity := bufferType.GetUpperBound(1) + 1;
    elementSize := bufferType.GetSize() / capacity;
    GetBufferInfo := TRUE;
ELSE
    capacity := 0;
    elementSize := 0;
    GetBufferInfo := FALSE;
END_IF
END_METHOD

METHOD Enqueue : BOOL
VAR_INPUT
    buffer      : VARIANT;
    item        : VARIANT;
    tail        : DINT;
    elementCount: DINT;
    elementSize : DINT;
END_VAR

VAR
    pDest : POINTER TO BYTE;
    pSrc  : POINTER TO BYTE;
    idx   : DINT;
END_VAR

idx := tail MOD THIS^._capacity;

pDest := __GET_VAR_DATA_REF(buffer).ADR + (idx * elementSize);
pSrc  := __GET_VAR_DATA_REF(item).ADR;

MemMove(pSrc, pDest, elementSize);

THIS^._tail := (tail + 1) MOD THIS^._capacity;
THIS^._elementCount := elementCount + 1;

Enqueue := TRUE;
END_METHOD

METHOD Dequeue : BOOL
VAR_INPUT
    buffer      : VARIANT;
    item        : VARIANT;
    head        : DINT;
    elementCount: DINT;
    elementSize : DINT;
END_VAR

VAR
    pSrc  : POINTER TO BYTE;
    pDest : POINTER TO BYTE;
    idx   : DINT;
    zeroBuf : ARRAY[0..255] OF BYTE;
END_VAR

idx := head MOD THIS^._capacity;

pSrc  := __GET_VAR_DATA_REF(buffer).ADR + (idx * elementSize);
pDest := __GET_VAR_DATA_REF(item).ADR;

MemMove(pSrc, pDest, elementSize);

MemSet(zeroBuf, 0, elementSize);
MemMove(zeroBuf, pSrc, elementSize);

THIS^._head := (head + 1) MOD THIS^._capacity;
THIS^._elementCount := elementCount - 1;

Dequeue := TRUE;
END_METHOD
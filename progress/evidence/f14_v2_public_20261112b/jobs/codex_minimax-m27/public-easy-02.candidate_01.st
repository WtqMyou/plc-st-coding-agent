FUNCTION_BLOCK FB_DualWordEdgeDetection
VAR_INPUT
    value : DWORD;
END_VAR

VAR_OUTPUT
    hasChanged      : BOOL;
    hasRisingEdges  : BOOL;
    risingBits      : DWORD;
    noOfRisingBits  : USINT;
    hasFallingEdges : BOOL;
    fallingBits     : DWORD;
    noOfFallingBits : USINT;
END_VAR

VAR
    prevValue    : DWORD;
    changedBits  : DWORD;
    bitPosition  : USINT;
    bitMask      : DWORD;
END_VAR

changedBits := value XOR prevValue;

risingBits  := changedBits AND value;
fallingBits := changedBits AND NOT value;

hasChanged      := (value <> prevValue);
hasRisingEdges  := (risingBits  <> 0);
hasFallingEdges := (fallingBits <> 0);

noOfRisingBits  := 0;
noOfFallingBits := 0;

FOR bitPosition := 0 TO 31 DO
    bitMask := SHL(DWORD#1, bitPosition);
    IF (risingBits AND bitMask) <> DWORD#0 THEN
        noOfRisingBits := noOfRisingBits + 1;
    END_IF
    IF (fallingBits AND bitMask) <> DWORD#0 THEN
        noOfFallingBits := noOfFallingBits + 1;
    END_IF
END_FOR

prevValue := value;

END_FUNCTION_BLOCK
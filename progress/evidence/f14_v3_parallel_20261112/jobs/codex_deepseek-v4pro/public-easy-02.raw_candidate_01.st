FUNCTION_BLOCK FB_DualWordEdgeDetection
VAR_INPUT
    value : DWORD;
END_VAR
VAR_OUTPUT
    hasChanged : BOOL;
    hasRisingEdges : BOOL;
    risingBits : DWORD;
    noOfRisingBits : USINT;
    hasFallingEdges : BOOL;
    fallingBits : DWORD;
    noOfFallingBits : USINT;
END_VAR
VAR
    previousValue : DWORD;
    changedMask : DWORD;
    countingRising : DWORD;
    countingFalling : DWORD;
END_VAR

changedMask := value XOR previousValue;
hasChanged := changedMask <> DWORD#0;

risingBits := value AND changedMask;
fallingBits := previousValue AND changedMask;

hasRisingEdges := risingBits <> DWORD#0;
hasFallingEdges := fallingBits <> DWORD#0;

noOfRisingBits := USINT#0;
countingRising := risingBits;
WHILE countingRising <> DWORD#0 DO
    noOfRisingBits := noOfRisingBits + USINT#1;
    countingRising := countingRising AND (countingRising - DWORD#1);
END_WHILE;

noOfFallingBits := USINT#0;
countingFalling := fallingBits;
WHILE countingFalling <> DWORD#0 DO
    noOfFallingBits := noOfFallingBits + USINT#1;
    countingFalling := countingFalling AND (countingFalling - DWORD#1);
END_WHILE;

previousValue := value;

END_FUNCTION_BLOCK
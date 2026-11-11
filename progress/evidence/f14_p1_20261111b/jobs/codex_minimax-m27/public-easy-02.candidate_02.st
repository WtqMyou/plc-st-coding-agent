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
    prevValue : DWORD;
END_VAR

// Detect if the input value has changed
hasChanged := (value <> prevValue);

// Rising edges: current value bit is 1 AND previous value bit was 0
risingBits := value AND (NOT prevValue);
hasRisingEdges := (risingBits <> 0);

// Falling edges: current value bit is 0 AND previous value bit was 1
fallingBits := (NOT value) AND prevValue;
hasFallingEdges := (fallingBits <> 0);

// Count the number of set bits in risingBits using bit manipulation
noOfRisingBits := 0;
VAR tempRising : DWORD; END_VAR
tempRising := risingBits;
WHILE tempRising <> 0 DO
    noOfRisingBits := noOfRisingBits + 1;
    tempRising := tempRising AND (tempRising - 1); // Clear lowest set bit
END_WHILE

// Count the number of set bits in fallingBits using bit manipulation
noOfFallingBits := 0;
VAR tempFalling : DWORD; END_VAR
tempFalling := fallingBits;
WHILE tempFalling <> 0 DO
    noOfFallingBits := noOfFallingBits + 1;
    tempFalling := tempFalling AND (tempFalling - 1); // Clear lowest set bit
END_WHILE

// Store current value for next cycle
prevValue := value;

END_FUNCTION_BLOCK
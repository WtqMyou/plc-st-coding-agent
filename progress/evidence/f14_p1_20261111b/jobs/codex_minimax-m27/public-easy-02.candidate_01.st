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

// Count the number of set bits in risingBits
noOfRisingBits := 0;
IF risingBits.0 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.1 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.2 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.3 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.4 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.5 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.6 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.7 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.8 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.9 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.10 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.11 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.12 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.13 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.14 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.15 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.16 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.17 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.18 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.19 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.20 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.21 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.22 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.23 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.24 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.25 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.26 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.27 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.28 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.29 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.30 THEN noOfRisingBits := noOfRisingBits + 1; END_IF
IF risingBits.31 THEN noOfRisingBits := noOfRisingBits + 1; END_IF

// Count the number of set bits in fallingBits
noOfFallingBits := 0;
IF fallingBits.0 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.1 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.2 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.3 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.4 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.5 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.6 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.7 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.8 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.9 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.10 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.11 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.12 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.13 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.14 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.15 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.16 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.17 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.18 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.19 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.20 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.21 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.22 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.23 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.24 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.25 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.26 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.27 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.28 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.29 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.30 THEN noOfFallingBits := noOfFallingBits + 1; END_IF
IF fallingBits.31 THEN noOfFallingBits := noOfFallingBits + 1; END_IF

// Store current value for next cycle
prevValue := value;

END_FUNCTION_BLOCK
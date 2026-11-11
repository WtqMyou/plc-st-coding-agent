FUNCTION_BLOCK FB_DualWordEdgeDetection
VAR
    prevValue   : DWORD;
    bitCounter  : DWORD;
    countRising : USINT;
    countFalling: USINT;
END_VAR

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

// ============================================================================
// Rising edge detection: current = 1 AND previous = 0
risingBits := value AND (NOT prevValue);

// Falling edge detection: current = 0 AND previous = 1
fallingBits := (NOT value) AND prevValue;

// Check if the entire value has changed
hasChanged := (value <> prevValue);

// Set boolean flags for edge detection
hasRisingEdges  := (risingBits <> 16#00000000);
hasFallingEdges := (fallingBits <> 16#00000000);

// ============================================================================
// Count rising edges using Brian Kernighan's algorithm
// ============================================================================
bitCounter  := risingBits;
countRising := 0;
WHILE bitCounter <> 0 DO
    bitCounter := bitCounter & (bitCounter - 1);
    countRising := countRising + 1;
END_WHILE
noOfRisingBits := countRising;

// ============================================================================
// Count falling edges using Brian Kernighan's algorithm
// ============================================================================
bitCounter   := fallingBits;
countFalling := 0;
WHILE bitCounter <> 0 DO
    bitCounter := bitCounter & (bitCounter - 1);
    countFalling := countFalling + 1;
END_WHILE
noOfFallingBits := countFalling;

// ============================================================================
// Store current value for next cycle edge detection
// ============================================================================
prevValue := value;

END_FUNCTION_BLOCK
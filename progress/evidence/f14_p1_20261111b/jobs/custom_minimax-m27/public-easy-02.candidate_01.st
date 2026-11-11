FUNCTION_BLOCK FB_DualWordEdgeDetection
VAR_OUTPUT
    hasChanged      : BOOL;
    hasRisingEdges  : BOOL;
    risingBits      : DWORD;
    noOfRisingBits  : USINT;
    hasFallingEdges : BOOL;
    fallingBits     : DWORD;
    noOfFallingBits : USINT;
END_VAR

VAR_INPUT
    value : DWORD;
END_VAR

VAR
    prevValue : DWORD;
END_VAR

// ============================================================================
// Internal Function: Count the number of set bits in a DWORD
// Uses Brian Kernighan's algorithm for efficiency
// ============================================================================
FUNCTION PRIVATE FB_CountBits : USINT
VAR_INPUT
    bits : DWORD;
END_VAR
VAR
    count : USINT := 0;
END_VAR
    WHILE bits <> 0 DO
        bits := bits & (bits - 1);
        count := count + 1;
    END_WHILE
    FB_CountBits := count;
END_FUNCTION

// ============================================================================
// Main Edge Detection Logic
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

// Count the number of set bits (edges) in each pattern
noOfRisingBits  := FB_CountBits(risingBits);
noOfFallingBits := FB_CountBits(fallingBits);

// Store current value for next cycle edge detection
prevValue := value;

END_FUNCTION_BLOCK
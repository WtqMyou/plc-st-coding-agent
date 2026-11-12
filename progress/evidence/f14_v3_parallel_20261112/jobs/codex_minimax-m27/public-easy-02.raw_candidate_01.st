FUNCTION_BLOCK FB_DualWordEdgeDetection
VAR_INPUT
END_VAR

VAR_OUTPUT
    hasChanged       : BOOL  := FALSE;
    hasRisingEdges   : BOOL  := FALSE;
    risingBits       : DWORD := 0;
    noOfRisingBits   : USINT := 0;
    hasFallingEdges  : BOOL  := FALSE;
    fallingBits      : DWORD := 0;
    noOfFallingBits  : USINT := 0;
END_VAR

VAR
    prevValue : DWORD := 0;
    bitMask   : DWORD;
    bitCount  : USINT;
END_VAR

// Detect rising edges: current=1 AND previous=0
risingBits := value AND (NOT prevValue);

// Detect falling edges: current=0 AND previous=1
fallingBits := (NOT value) AND prevValue;

// Set change indicators
hasChanged := (risingBits OR fallingBits) <> 0;
hasRisingEdges := risingBits <> 0;
hasFallingEdges := fallingBits <> 0;

// Count rising bits
bitMask := risingBits;
noOfRisingBits := 0;
FOR bitCount := 0 TO 31 DO
    IF (bitMask AND 1) = 1 THEN
        noOfRisingBits := noOfRisingBits + 1;
    END_IF;
    bitMask := SHR(bitMask, 1);
END_FOR;

// Count falling bits
bitMask := fallingBits;
noOfFallingBits := 0;
FOR bitCount := 0 TO 31 DO
    IF (bitMask AND 1) = 1 THEN
        noOfFallingBits := noOfFallingBits + 1;
    END_IF;
    bitMask := SHR(bitMask, 1);
END_FOR;

// Store current value for next scan
prevValue := value;

END_FUNCTION_BLOCK
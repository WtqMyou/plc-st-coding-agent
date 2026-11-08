FUNCTION_BLOCK FB
VAR_INPUT
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
    prevValue : DWORD := 0;
    bitCheck  : DWORD;
    i         : USINT;
END_VAR

// Calculate rising edges: current=1 AND previous=0
risingBits := value AND NOT prevValue;

// Calculate falling edges: current=0 AND previous=1
fallingBits := NOT value AND prevValue;

// Detect if value has changed
hasChanged := (value <> prevValue);

// Set edge flags based on bit streams
hasRisingEdges := (risingBits <> 0);
hasFallingEdges := (fallingBits <> 0);

// Count rising bits
noOfRisingBits := 0;
bitCheck := risingBits;
FOR i := 0 TO 31 DO
    IF (bitCheck AND 1) = 1 THEN
        noOfRisingBits := noOfRisingBits + 1;
    END_IF;
    bitCheck := SHR(bitCheck, 1);
END_FOR;

// Count falling bits
noOfFallingBits := 0;
bitCheck := fallingBits;
FOR i := 0 TO 31 DO
    IF (bitCheck AND 1) = 1 THEN
        noOfFallingBits := noOfFallingBits + 1;
    END_IF;
    bitCheck := SHR(bitCheck, 1);
END_FOR;

// Update history for next cycle
prevValue := value;
END_FUNCTION_BLOCK
FUNCTION_BLOCK FB_EdgeDetection
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
    prevValue   : DWORD;
    tmpRising   : DWORD;
    tmpFalling  : DWORD;
    i           : USINT;
END_VAR

    // Detect rising and falling edges for each bit
    risingBits  := value AND NOT prevValue;
    fallingBits := prevValue AND NOT value;

    // Determine if any change occurred
    hasChanged      := (risingBits OR fallingBits) <> #0;
    hasRisingEdges  := risingBits <> #0;
    hasFallingEdges := fallingBits <> #0;

    // Count rising edges
    tmpRising      := risingBits;
    noOfRisingBits := 0;
    FOR i := 0 TO 31 DO
        IF (tmpRising AND 1) = 1 THEN
            noOfRisingBits := noOfRisingBits + 1;
        END_IF
        tmpRising := SHR(tmpRising, 1);
    END_FOR

    // Count falling edges
    tmpFalling     := fallingBits;
    noOfFallingBits := 0;
    FOR i := 0 TO 31 DO
        IF (tmpFalling AND 1) = 1 THEN
            noOfFallingBits := noOfFallingBits + 1;
        END_IF
        tmpFalling := SHR(tmpFalling, 1);
    END_FOR

    // Store current value for next cycle
    prevValue := value;
END_FUNCTION_BLOCK
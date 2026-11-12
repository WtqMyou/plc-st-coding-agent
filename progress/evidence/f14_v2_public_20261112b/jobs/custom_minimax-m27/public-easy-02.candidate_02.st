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
    firstCycle  : BOOL := TRUE;
END_VAR

    IF firstCycle THEN
        prevValue   := value;
        firstCycle  := FALSE;
        hasChanged      := FALSE;
        hasRisingEdges  := FALSE;
        risingBits      := 0;
        noOfRisingBits  := 0;
        hasFallingEdges := FALSE;
        fallingBits     := 0;
        noOfFallingBits := 0;
    ELSE
        risingBits  := value AND NOT prevValue;
        fallingBits := prevValue AND NOT value;

        hasChanged      := (risingBits OR fallingBits) <> 0;
        hasRisingEdges  := risingBits <> 0;
        hasFallingEdges := fallingBits <> 0;

        tmpRising      := risingBits;
        noOfRisingBits := 0;
        FOR i := 0 TO 31 DO
            IF (tmpRising AND 1) = 1 THEN
                noOfRisingBits := noOfRisingBits + 1;
            END_IF;
            tmpRising := SHR(tmpRising, 1);
        END_FOR;

        tmpFalling      := fallingBits;
        noOfFallingBits := 0;
        FOR i := 0 TO 31 DO
            IF (tmpFalling AND 1) = 1 THEN
                noOfFallingBits := noOfFallingBits + 1;
            END_IF;
            tmpFalling := SHR(tmpFalling, 1);
        END_FOR;

        prevValue := value;
    END_IF;
END_FUNCTION_BLOCK
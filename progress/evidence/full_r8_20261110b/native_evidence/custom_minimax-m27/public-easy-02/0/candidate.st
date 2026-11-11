FUNCTION_BLOCK FB
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
    prevValue       : DWORD := 0;
    tempRisingBits  : DWORD;
    tempFallingBits : DWORD;
    cntRising       : USINT;
    cntFalling      : USINT;
    i               : USINT;
END_VAR

// Detect edges between current and previous values
tempRisingBits  := value AND (NOT prevValue);
tempFallingBits := prevValue AND (NOT value);

// Assign edge bit streams to outputs
risingBits  := tempRisingBits;
fallingBits := tempFallingBits;

// Set change and edge flags
hasChanged      := (tempRisingBits <> 0) OR (tempFallingBits <> 0);
hasRisingEdges  := (tempRisingBits <> 0);
hasFallingEdges := (tempFallingBits <> 0);

// Count the number of set bits (rising edges)
cntRising  := 0;
cntFalling := 0;
FOR i := 0 TO 31 DO
    IF (tempRisingBits AND SHL(DWORD#1, i)) <> DWORD#0 THEN
        cntRising := cntRising + 1;
    END_IF
    IF (tempFallingBits AND SHL(DWORD#1, i)) <> DWORD#0 THEN
        cntFalling := cntFalling + 1;
    END_IF
END_FOR

noOfRisingBits  := cntRising;
noOfFallingBits := cntFalling;

// Store current value for next scan cycle
prevValue := value;
END_FUNCTION_BLOCK
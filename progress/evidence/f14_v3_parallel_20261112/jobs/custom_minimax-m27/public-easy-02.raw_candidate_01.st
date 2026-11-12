FUNCTION_BLOCK FB_DualWordEdgeDetection
VAR
    prevValue : DWORD;
END_VAR

VAR_OUTPUT
    hasChanged      : BOOL := FALSE;
    hasRisingEdges  : BOOL := FALSE;
    risingBits      : DWORD := 0;
    noOfRisingBits  : USINT := 0;
    hasFallingEdges : BOOL := FALSE;
    fallingBits     : DWORD := 0;
    noOfFallingBits : USINT := 0;
END_VAR

VAR
    i : USINT;
END_VAR

risingBits  := value AND NOT prevValue;
fallingBits := NOT value AND prevValue;
hasChanged      := (value <> prevValue);
hasRisingEdges  := (risingBits <> 0);
hasFallingEdges := (fallingBits <> 0);

noOfRisingBits  := 0;
noOfFallingBits := 0;

FOR i := 0 TO 31 DO
    IF (risingBits AND SHL(DWORD#1, i)) <> 0 THEN
        noOfRisingBits := noOfRisingBits + 1;
    END_IF;
    IF (fallingBits AND SHL(DWORD#1, i)) <> 0 THEN
        noOfFallingBits := noOfFallingBits + 1;
    END_IF;
END_FOR;

prevValue := value;
END_FUNCTION_BLOCK
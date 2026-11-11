FUNCTION_BLOCK DualWordEdgeDetector
VAR_INPUT
    value : DWORD;
END_VAR
VAR_OUTPUT
    hasChanged       : BOOL;
    hasRisingEdges   : BOOL;
    risingBits       : DWORD;
    noOfRisingBits   : USINT;
    hasFallingEdges  : BOOL;
    fallingBits      : DWORD;
    noOfFallingBits  : USINT;
END_VAR
VAR
    prevValue : DWORD;
    i : INT;
END_VAR

risingBits := value AND NOT prevValue;
fallingBits := NOT value AND prevValue;

hasRisingEdges := risingBits <> 0;
hasFallingEdges := fallingBits <> 0;
hasChanged := value <> prevValue;

noOfRisingBits := 0;
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
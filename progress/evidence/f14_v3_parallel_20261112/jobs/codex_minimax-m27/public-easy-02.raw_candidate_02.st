FUNCTION_BLOCK FB_DualWordEdgeDetection
VAR_INPUT
    value : DWORD;
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
    tmpBits   : DWORD;
END_VAR

risingBits := value AND (NOT prevValue);
fallingBits := (NOT value) AND prevValue;

hasChanged := risingBits <> 0 OR fallingBits <> 0;
hasRisingEdges := risingBits <> 0;
hasFallingEdges := fallingBits <> 0;

tmpBits := risingBits;
noOfRisingBits := 0;
WHILE tmpBits <> 0 DO
    noOfRisingBits := noOfRisingBits + 1;
    tmpBits := SHR(tmpBits, 1);
END_WHILE;

tmpBits := fallingBits;
noOfFallingBits := 0;
WHILE tmpBits <> 0 DO
    noOfFallingBits := noOfFallingBits + 1;
    tmpBits := SHR(tmpBits, 1);
END_WHILE;

prevValue := value;

END_FUNCTION_BLOCK
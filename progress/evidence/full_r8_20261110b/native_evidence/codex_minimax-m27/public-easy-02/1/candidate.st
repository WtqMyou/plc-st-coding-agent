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
    prevValue : DWORD := 0;
    i         : USINT;
    tmpRising : DWORD;
    tmpFalling: DWORD;
END_VAR

tmpRising  := NOT prevValue;
tmpFalling := prevValue;

risingBits  := value AND tmpRising;
fallingBits := tmpFalling AND NOT value;

noOfRisingBits  := 0;
noOfFallingBits := 0;

FOR i := 0 TO 31 DO
    noOfRisingBits  := noOfRisingBits + TO_USINT((risingBits  SHR TO_USINT(i)) AND 1);
    noOfFallingBits := noOfFallingBits + TO_USINT((fallingBits SHR TO_USINT(i)) AND 1);
END_FOR

hasChanged      := (risingBits <> 0) OR (fallingBits <> 0);
hasRisingEdges  := risingBits <> 0;
hasFallingEdges := fallingBits <> 0;

prevValue := value;
END_FUNCTION_BLOCK
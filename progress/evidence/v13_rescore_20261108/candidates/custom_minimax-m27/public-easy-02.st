FUNCTION_BLOCK FB
VAR_INPUT
    value   : DWORD;
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
    prevValue : DWORD;
    i         : USINT;
    bitMask   : DWORD;
END_VAR

(* Detect edges *)
risingBits  := value AND NOT prevValue;
fallingBits := prevValue AND NOT value;
hasChanged  := (value <> prevValue);
hasRisingEdges  := (risingBits <> 0);
hasFallingEdges := (fallingBits <> 0);

(* Count set bits *)
noOfRisingBits  := 0;
noOfFallingBits := 0;
FOR i := 0 TO 31 DO
    bitMask := SHL(DWORD#1, i);
    IF (risingBits AND bitMask) <> 0 THEN
        noOfRisingBits := noOfRisingBits + 1;
    END_IF
    IF (fallingBits AND bitMask) <> 0 THEN
        noOfFallingBits := noOfFallingBits + 1;
    END_IF
END_FOR

(* Update history *)
prevValue := value;

END_FUNCTION_BLOCK
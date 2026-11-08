FUNCTION_BLOCK FB
VAR_INPUT
    value : DWORD;
END_VAR
VAR_OUTPUT
    hasChanged : BOOL;
    hasRisingEdges : BOOL;
    risingBits : DWORD;
    noOfRisingBits : USINT;
    hasFallingEdges : BOOL;
    fallingBits : DWORD;
    noOfFallingBits : USINT;
END_VAR
VAR
    previousValue : DWORD := 0;
    bitIndex : USINT;
END_VAR

risingBits := value AND (NOT previousValue);
fallingBits := (NOT value) AND previousValue;

noOfRisingBits := 0;
noOfFallingBits := 0;

FOR bitIndex := 0 TO 31 DO
    IF (risingBits AND SHL(DWORD#1, bitIndex)) <> 0 THEN
        noOfRisingBits := noOfRisingBits + 1;
    END_IF;
    IF (fallingBits AND SHL(DWORD#1, bitIndex)) <> 0 THEN
        noOfFallingBits := noOfFallingBits + 1;
    END_IF;
END_FOR;

hasRisingEdges := (risingBits <> 0);
hasFallingEdges := (fallingBits <> 0);
hasChanged := hasRisingEdges OR hasFallingEdges;

previousValue := value;

END_FUNCTION_BLOCK
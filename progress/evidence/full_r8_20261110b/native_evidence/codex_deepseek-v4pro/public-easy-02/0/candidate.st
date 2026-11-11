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
    prevValue : DWORD;
    bitIndex : INT;
END_VAR

risingBits := value AND (NOT prevValue);
fallingBits := prevValue AND (NOT value);

hasRisingEdges := risingBits <> DWORD#0;
hasFallingEdges := fallingBits <> DWORD#0;
hasChanged := hasRisingEdges OR hasFallingEdges;

noOfRisingBits := 0;
noOfFallingBits := 0;

FOR bitIndex := 0 TO 31 DO
    IF ((risingBits SHR bitIndex) AND DWORD#1) <> DWORD#0 THEN
        noOfRisingBits := noOfRisingBits + 1;
    END_IF;

    IF ((fallingBits SHR bitIndex) AND DWORD#1) <> DWORD#0 THEN
        noOfFallingBits := noOfFallingBits + 1;
    END_IF;
END_FOR;

prevValue := value;
END_FUNCTION_BLOCK
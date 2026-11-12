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
    lastValue : DWORD;
    bitIndex : INT;
END_VAR

risingBits := (NOT lastValue) AND value;
fallingBits := lastValue AND (NOT value);

hasChanged := lastValue <> value;
hasRisingEdges := risingBits <> DWORD#0;
hasFallingEdges := fallingBits <> DWORD#0;

noOfRisingBits := USINT#0;
noOfFallingBits := USINT#0;

FOR bitIndex := 0 TO 31 DO
    IF ((SHR(risingBits, bitIndex) AND DWORD#1) <> DWORD#0) THEN
        noOfRisingBits := noOfRisingBits + USINT#1;
    END_IF;

    IF ((SHR(fallingBits, bitIndex) AND DWORD#1) <> DWORD#0) THEN
        noOfFallingBits := noOfFallingBits + USINT#1;
    END_IF;
END_FOR;

lastValue := value;

END_FUNCTION_BLOCK
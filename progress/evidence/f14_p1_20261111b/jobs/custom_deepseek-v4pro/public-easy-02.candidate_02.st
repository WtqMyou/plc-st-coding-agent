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
    firstScan : BOOL := TRUE;
    i : INT;
END_VAR

IF firstScan THEN
    prevValue := value;
    hasChanged := FALSE;
    hasRisingEdges := FALSE;
    risingBits := 0;
    noOfRisingBits := 0;
    hasFallingEdges := FALSE;
    fallingBits := 0;
    noOfFallingBits := 0;
    firstScan := FALSE;
ELSE
    risingBits := (NOT prevValue) AND value;
    fallingBits := prevValue AND (NOT value);
    
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
    
    hasChanged := (value <> prevValue);
    hasRisingEdges := (risingBits <> 0);
    hasFallingEdges := (fallingBits <> 0);
    
    prevValue := value;
END_IF;

END_FUNCTION_BLOCK
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
    lastValue : DWORD := 0;
    i : INT;
    countRise : USINT;
    countFall : USINT;
END_VAR

risingBits := (NOT lastValue) AND value;
fallingBits := lastValue AND (NOT value);
hasChanged := (value <> lastValue);
hasRisingEdges := (risingBits <> 0);
hasFallingEdges := (fallingBits <> 0);

countRise := 0;
FOR i := 0 TO 31 DO
    IF (risingBits AND SHL(DWORD#1, i)) <> 0 THEN
        countRise := countRise + 1;
    END_IF;
END_FOR;
noOfRisingBits := countRise;

countFall := 0;
FOR i := 0 TO 31 DO
    IF (fallingBits AND SHL(DWORD#1, i)) <> 0 THEN
        countFall := countFall + 1;
    END_IF;
END_FOR;
noOfFallingBits := countFall;

lastValue := value;

END_FUNCTION_BLOCK
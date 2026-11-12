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
    firstRun : BOOL := TRUE;
    i : INT;
    mask : DWORD;
    countRise : USINT;
    countFall : USINT;
END_VAR

IF firstRun THEN
    lastValue := value;
    firstRun := FALSE;
    hasChanged := FALSE;
    hasRisingEdges := FALSE;
    risingBits := 0;
    noOfRisingBits := 0;
    hasFallingEdges := FALSE;
    fallingBits := 0;
    noOfFallingBits := 0;
    RETURN;
END_IF;

hasChanged := (value <> lastValue);
risingBits := (NOT lastValue) AND value;
fallingBits := lastValue AND (NOT value);
hasRisingEdges := (risingBits <> 0);
hasFallingEdges := (fallingBits <> 0);

countRise := 0;
FOR i := 0 TO 31 DO
    mask := SHL(DWORD#1, i);
    IF (risingBits AND mask) <> 0 THEN
        countRise := countRise + 1;
    END_IF;
END_FOR;
noOfRisingBits := countRise;

countFall := 0;
FOR i := 0 TO 31 DO
    mask := SHL(DWORD#1, i);
    IF (fallingBits AND mask) <> 0 THEN
        countFall := countFall + 1;
    END_IF;
END_FOR;
noOfFallingBits := countFall;

lastValue := value;

END_FUNCTION_BLOCK
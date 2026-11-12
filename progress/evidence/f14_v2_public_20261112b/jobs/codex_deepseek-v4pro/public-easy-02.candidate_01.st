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
    firstCycle : BOOL := TRUE;
    bitMask : DWORD;
    bitIndex : INT;
END_VAR

noOfRisingBits := USINT#0;
noOfFallingBits := USINT#0;

IF firstCycle THEN
    lastValue := value;
    firstCycle := FALSE;
    hasChanged := FALSE;
    hasRisingEdges := FALSE;
    risingBits := DWORD#0;
    hasFallingEdges := FALSE;
    fallingBits := DWORD#0;
ELSE
    hasChanged := (lastValue <> value);
    risingBits := (NOT lastValue) AND value;
    fallingBits := lastValue AND (NOT value);

    hasRisingEdges := (risingBits <> DWORD#0);
    hasFallingEdges := (fallingBits <> DWORD#0);

    FOR bitIndex := 0 TO 31 DO
        bitMask := SHL(DWORD#1, bitIndex);
        IF ((risingBits AND bitMask) <> DWORD#0) THEN
            noOfRisingBits := noOfRisingBits + USINT#1;
        END_IF;
        IF ((fallingBits AND bitMask) <> DWORD#0) THEN
            noOfFallingBits := noOfFallingBits + USINT#1;
        END_IF;
    END_FOR;

    lastValue := value;
END_IF;

END_FUNCTION_BLOCK
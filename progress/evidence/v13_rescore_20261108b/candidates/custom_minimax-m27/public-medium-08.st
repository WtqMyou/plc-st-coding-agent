FUNCTION_BLOCK FB
VAR_INPUT
    ipText: STRING(254);
END_VAR
VAR_OUTPUT
    ipValue: UDINT;
END_VAR
VAR
    len         : INT;
    pos         : INT;
    c           : CHAR;
    segCount    : INT;
    curVal      : UDINT;
    inSegment   : BOOL;
    segValues   : ARRAY[1..4] OF BYTE;
    ok          : BOOL;
END_VAR

// Reset outputs and internal state each cycle
ipValue   := 0;
ok        := TRUE;
segCount  := 0;
curVal    := 0;
inSegment := FALSE;

// Length of input string
len := LEN(ipText);
pos := 1;

// Parse characters
WHILE (pos <= len) AND ok DO
    c := ipText[pos];
    IF c = '.' THEN
        // End of current segment
        IF NOT inSegment THEN
            ok := FALSE;          // empty segment
            EXIT;
        END_IF
        // Store segment value
        segCount := segCount + 1;
        IF segCount > 4 THEN
            ok := FALSE;
            EXIT;
        END_IF
        segValues[segCount] := TO_BYTE(curVal);
        // Prepare for next segment
        curVal    := 0;
        inSegment := FALSE;
    ELSE
        // Expect decimal digit
        IF (c >= '0') AND (c <= '9') THEN
            curVal := curVal * 10 + UDINT(CHAR_TO_INT(c) - 48);
            IF curVal > 255 THEN
                ok := FALSE;
                EXIT;
            END_IF
            inSegment := TRUE;
        ELSE
            ok := FALSE;
            EXIT;
        END_IF
    END_IF
    pos := pos + 1;
END_WHILE

// Handle the last segment (if any)
IF ok THEN
    IF inSegment THEN
        segCount := segCount + 1;
        IF segCount > 4 THEN
            ok := FALSE;
        ELSE
            segValues[segCount] := TO_BYTE(curVal);
        END_IF
    ELSE
        // No digits after last dot or empty final segment
        ok := FALSE;
    END_IF
END_IF

// Assemble the 32‑bit address in network byte order
IF ok AND (segCount = 4) THEN
    ipValue := SHL(UDINT(segValues[1]), 24) OR
               SHL(UDINT(segValues[2]), 16) OR
               SHL(UDINT(segValues[3]), 8)  OR
               UDINT(segValues[4]);
ELSE
    ipValue := 0;
END_IF

END_FUNCTION_BLOCK
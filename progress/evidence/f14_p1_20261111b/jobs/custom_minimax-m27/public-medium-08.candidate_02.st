FUNCTION_BLOCK FB_ParseIPv4
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    i           : INT;
    length      : INT;
    segmentIdx  : INT;
    segValue    : UDINT;
    isValid     : BOOL;
    curChar     : STRING(1);
    segments    : ARRAY[0..3] OF UDINT;
END_VAR

// Initialize output to invalid state
ipValue := 0;
isValid := TRUE;
segmentIdx := 0;
segValue := 0;
length := LEN(ipText);

// Empty input check
IF length = 0 THEN
    RETURN;
END_IF

// Parse through each character
FOR i := 1 TO length DO
    curChar := MID(ipText, 1, i);

    // Digit check: compare STRING(1) to character literals
    IF curChar = '0' OR curChar = '1' OR curChar = '2' OR 
       curChar = '3' OR curChar = '4' OR curChar = '5' OR 
       curChar = '6' OR curChar = '7' OR curChar = '8' OR 
       curChar = '9' THEN
        
        // Check for overflow before accumulating
        IF segValue > 25 OR (segValue = 25 AND curChar > '5') THEN
            isValid := FALSE;
            EXIT;
        END_IF;

        // Accumulate digit value (convert char to numeric)
        IF curChar = '0' THEN segValue := segValue * 10 + 0;
        ELSIF curChar = '1' THEN segValue := segValue * 10 + 1;
        ELSIF curChar = '2' THEN segValue := segValue * 10 + 2;
        ELSIF curChar = '3' THEN segValue := segValue * 10 + 3;
        ELSIF curChar = '4' THEN segValue := segValue * 10 + 4;
        ELSIF curChar = '5' THEN segValue := segValue * 10 + 5;
        ELSIF curChar = '6' THEN segValue := segValue * 10 + 6;
        ELSIF curChar = '7' THEN segValue := segValue * 10 + 7;
        ELSIF curChar = '8' THEN segValue := segValue * 10 + 8;
        ELSIF curChar = '9' THEN segValue := segValue * 10 + 9;
        END_IF

    // Period: segment delimiter
    ELSIF curChar = '.' THEN
        IF segmentIdx >= 4 THEN
            isValid := FALSE;
            EXIT;
        END_IF;

        segments[segmentIdx] := segValue;
        segmentIdx := segmentIdx + 1;
        segValue := 0;

    // Any other character is invalid
    ELSE
        isValid := FALSE;
        EXIT;
    END_IF
END_FOR

// Process final segment
IF isValid THEN
    IF segmentIdx >= 4 THEN
        isValid := FALSE;
    ELSE
        segments[segmentIdx] := segValue;
        segmentIdx := segmentIdx + 1;
    END_IF
END_IF

// Validate exactly 4 segments
IF isValid AND segmentIdx <> 4 THEN
    isValid := FALSE;
END_IF

// Assemble result in network byte order (MSB first)
IF isValid THEN
    ipValue := SHL(segments[0], 24) OR SHL(segments[1], 16) 
             OR SHL(segments[2], 8)  OR segments[3];
ELSE
    ipValue := 0;
END_IF

END_FUNCTION_BLOCK
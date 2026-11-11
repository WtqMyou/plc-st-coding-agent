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
    ch          : BYTE;
    digit       : BYTE;
    segments    : ARRAY[0..3] OF UDINT;
END_VAR

// Initialize output to invalid state
ipValue := 0;

// Reset parsing state
isValid    := TRUE;
segmentIdx := 0;
segValue   := 0;
length     := LEN(ipText);

// Empty input check
IF length = 0 THEN
    RETURN;
END_IF

// Parse through each character
FOR i := 1 TO length DO
    ch := BYTE_TO_INT(CHAR_TO_BYTE(MID(ipText, 1, i)));

    // Digit: 0-9 ASCII range 48-57
    IF ch >= 48 AND ch <= 57 THEN
        digit := ch - 48;

        // Check for overflow before multiplying
        // Max valid segment is 255
        // If current value > 25, multiplying by 10 would exceed 255
        // If current value = 25, digit > 5 would exceed 255
        IF segValue > 25 OR (segValue = 25 AND digit > 5) THEN
            isValid := FALSE;
            EXIT;
        END_IF;

        segValue := segValue * 10 + digit;

    // Period: segment delimiter
    ELSIF ch = 46 THEN
        IF segmentIdx > 3 THEN
            isValid := FALSE;
            EXIT;
        END_IF;

        segments[segmentIdx] := segValue;
        segmentIdx := segmentIdx + 1;
        segValue   := 0;

    // Any other character is invalid
    ELSE
        isValid := FALSE;
        EXIT;
    END_IF
END_FOR

// Process final segment
IF isValid THEN
    IF segmentIdx > 3 THEN
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
// ipValue[31:24] = segments[0]
// ipValue[23:16] = segments[1]
// ipValue[15:8]  = segments[2]
// ipValue[7:0]   = segments[3]
IF isValid THEN
    ipValue := SHL(segments[0], 24) OR SHL(segments[1], 16) 
             OR SHL(segments[2], 8)  OR segments[3];
ELSE
    ipValue := 0;
END_IF

END_FUNCTION_BLOCK
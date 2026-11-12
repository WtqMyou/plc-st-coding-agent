FUNCTION_BLOCK IPv4Parser
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    currentPos : INT;
    segmentLen : INT;
    segmentValue : UDINT;
    dotCount : INT;
    charCode : INT;
    ch : CHAR;
END_VAR

ipValue := 0;

// Basic length validation
IF LEN(ipText) < 7 OR LEN(ipText) > 15 THEN
    RETURN;
END_IF

currentPos := 1;
dotCount := 0;

WHILE dotCount < 3 AND currentPos <= LEN(ipText) DO
    // Extract one segment
    segmentValue := 0;
    segmentLen := 0;
    
    WHILE currentPos <= LEN(ipText) DO
        ch := MID(ipText, 1, currentPos);
        charCode := CHAR_TO_INT(ch);
        
        IF charCode = 46 THEN // '.'
            EXIT;
        ELSIF charCode >= 48 AND charCode <= 57 THEN
            segmentValue := segmentValue * 10 + TO_UDINT(charCode - 48);
            segmentLen := segmentLen + 1;
            currentPos := currentPos + 1;
        ELSE
            ipValue := 0;
            RETURN;
        END_IF
    END_WHILE
    
    // Validate segment
    IF segmentLen = 0 OR segmentLen > 3 THEN
        ipValue := 0;
        RETURN;
    END_IF
    
    IF segmentValue > 255 THEN
        ipValue := 0;
        RETURN;
    END_IF
    
    // Add to result in network byte order
    ipValue := SHL(ipValue, 8) OR segmentValue;
    dotCount := dotCount + 1;
    
    // Move to next position after dot
    currentPos := currentPos + 1;
END_WHILE

// Validate exactly 3 dots (4 segments)
IF dotCount <> 3 THEN
    ipValue := 0;
    RETURN;
END_IF

// Ensure no content after 4th segment
IF currentPos <= LEN(ipText) THEN
    ipValue := 0;
    RETURN;
END_IF

END_FUNCTION_BLOCK
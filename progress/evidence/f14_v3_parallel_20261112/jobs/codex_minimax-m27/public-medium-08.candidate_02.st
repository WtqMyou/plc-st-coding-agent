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
    ch : STRING(1);
    charVal : INT;
END_VAR

ipValue := 0;

// Basic length validation
IF LEN(ipText) < 7 OR LEN(ipText) > 15 THEN
    RETURN;
END_IF;

currentPos := 1;
dotCount := 0;

WHILE dotCount < 3 AND currentPos <= LEN(ipText) DO
    segmentValue := 0;
    segmentLen := 0;
    
    WHILE currentPos <= LEN(ipText) DO
        ch := MID(ipText, 1, currentPos);
        
        IF LEN(ch) = 1 AND MID(ch, 1, 1) = '.' THEN
            EXIT;
        END_IF;
        
        charVal := INT(MID(ipText, 1, currentPos));
        
        IF charVal >= 48 AND charVal <= 57 THEN
            segmentValue := segmentValue * 10 + UDINT(DINT(charVal - 48));
            segmentLen := segmentLen + 1;
            currentPos := currentPos + 1;
        ELSE
            ipValue := 0;
            RETURN;
        END_IF;
    END_WHILE;
    
    IF segmentLen = 0 OR segmentLen > 3 THEN
        ipValue := 0;
        RETURN;
    END_IF;
    
    IF segmentValue > 255 THEN
        ipValue := 0;
        RETURN;
    END_IF;
    
    ipValue := SHL(ipValue, 8) OR segmentValue;
    dotCount := dotCount + 1;
    
    IF currentPos <= LEN(ipText) THEN
        currentPos := currentPos + 1;
    END_IF;
END_WHILE;

IF dotCount <> 3 THEN
    ipValue := 0;
    RETURN;
END_IF;

IF currentPos <= LEN(ipText) AND MID(ipText, 1, currentPos) <> '.' THEN
    ipValue := 0;
    RETURN;
END_IF;

END_FUNCTION_BLOCK
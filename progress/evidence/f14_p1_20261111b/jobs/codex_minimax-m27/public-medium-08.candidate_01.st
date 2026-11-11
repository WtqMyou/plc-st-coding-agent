FUNCTION_BLOCK FB_IPv4Parse
    VAR_INPUT
        ipText : STRING(254);
    END_VAR
    VAR_OUTPUT
        ipValue : UDINT;
    END_VAR
    VAR
        pos : INT;
        segmentStart : INT;
        segmentLen : INT;
        segmentCount : INT;
        value : INT;
        ch : CHAR;
        textLen : INT;
    END_VAR

    ipValue := 0;
    textLen := LEN(ipText);
    pos := 1;
    segmentCount := 0;
    
    // Skip leading whitespace
    WHILE (pos <= textLen) AND (MID(ipText, 1, pos) = ' ') DO
        pos := pos + 1;
    END_WHILE;
    
    // Parse up to 4 segments
    WHILE (segmentCount < 4) AND (pos <= textLen) DO
        segmentStart := pos;
        segmentLen := 0;
        
        // Collect digits for current segment
        WHILE (pos <= textLen) DO
            ch := MID(ipText, 1, pos);
            IF ch = '.' THEN
                EXIT;
            END_IF;
            IF (ch < '0') OR (ch > '9') THEN
                ipValue := 0;
                RETURN;
            END_IF;
            segmentLen := segmentLen + 1;
            pos := pos + 1;
        END_WHILE;
        
        // Check segment length (1-3 digits for valid 0-255)
        IF segmentLen < 1 OR segmentLen > 3 THEN
            ipValue := 0;
            RETURN;
        END_IF;
        
        // Parse segment value
        value := 0;
        FOR pos := segmentStart TO segmentStart + segmentLen - 1 DO
            ch := MID(ipText, 1, pos);
            value := value * 10 + (ch - '0');
        END_FOR;
        
        // Validate segment range
        IF value > 255 THEN
            ipValue := 0;
            RETURN;
        END_IF;
        
        // Accumulate result in network byte order
        ipValue := (ipValue << 8) OR TO_UDINT(value);
        segmentCount := segmentCount + 1;
        
        // Skip the dot separator if present
        IF (pos <= textLen) AND (MID(ipText, 1, pos) = '.') THEN
            pos := pos + 1;
        END_IF;
    END_WHILE;
    
    // Validate we have exactly 4 segments
    IF segmentCount <> 4 THEN
        ipValue := 0;
        RETURN;
    END_IF;
    
    // Skip trailing whitespace
    WHILE (pos <= textLen) AND (MID(ipText, 1, pos) = ' ') DO
        pos := pos + 1;
    END_WHILE;
    
    // If there's more content after the 4 segments (other than whitespace), it's invalid
    IF pos <= textLen THEN
        ipValue := 0;
        RETURN;
    END_IF;

END_FUNCTION_BLOCK
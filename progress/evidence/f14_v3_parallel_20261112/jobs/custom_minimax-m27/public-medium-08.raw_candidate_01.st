FUNCTION_BLOCK FB_ParseIPv4
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    i : UINT;
    dot1 : UINT;
    dot2 : UINT;
    dot3 : UINT;
    len : UINT;
    seg1 : STRING(4);
    seg2 : STRING(4);
    seg3 : STRING(4);
    seg4 : STRING(4);
    seg1Len : UINT;
    seg2Len : UINT;
    seg3Len : UINT;
    seg4Len : UINT;
    val1 : UDINT;
    val2 : UDINT;
    val3 : UDINT;
    val4 : UDINT;
    result : UDINT;
    valid : BOOL;
    ch : CHAR;
END_VAR

result := 0;
valid := TRUE;

len := LEN(ipText);

IF len = 0 OR len > 254 THEN
    valid := FALSE;
END_IF

IF valid THEN
    dot1 := FIND(ipText, '.');
    IF dot1 <= 1 OR dot1 >= 254 THEN
        valid := FALSE;
    END_IF
END_IF

IF valid THEN
    dot2 := FIND(MID(ipText, 254 - dot1, dot1 + 1), '.');
    IF dot2 > 0 THEN
        dot2 := dot2 + dot1;
    END_IF;
END_IF;

IF valid THEN
    dot3 := 0;
    IF dot2 > 0 AND dot2 < 254 THEN
        dot3 := FIND(MID(ipText, 254 - dot2, dot2 + 1), '.');
        IF dot3 > 0 THEN
            dot3 := dot3 + dot2;
        END_IF;
    END_IF;
END_IF;

IF valid THEN
    IF dot1 = 0 OR dot2 = 0 OR dot3 = 0 THEN
        valid := FALSE;
    END_IF;
END_IF;

IF valid THEN
    seg1Len := dot1 - 1;
    seg2Len := dot2 - dot1 - 1;
    seg3Len := dot3 - dot2 - 1;
    seg4Len := len - dot3;
    
    IF seg1Len < 1 OR seg1Len > 3 OR seg2Len < 1 OR seg2Len > 3 OR 
       seg3Len < 1 OR seg3Len > 3 OR seg4Len < 1 OR seg4Len > 3 THEN
        valid := FALSE;
    END_IF;
END_IF;

IF valid THEN
    seg1 := LEFT(ipText, seg1Len);
    seg2 := MID(ipText, seg2Len, dot1 + 1);
    seg3 := MID(ipText, seg3Len, dot2 + 1);
    seg4 := RIGHT(ipText, seg4Len);
    
    valid := (seg1Len = LEN(seg1)) AND (seg2Len = LEN(seg2)) AND 
             (seg3Len = LEN(seg3)) AND (seg4Len = LEN(seg4));
END_IF;

IF valid THEN
    valid := FALSE;
    val1 := STRING_TO_UDINT(seg1);
    val2 := STRING_TO_UDINT(seg2);
    val3 := STRING_TO_UDINT(seg3);
    val4 := STRING_TO_UDINT(seg4);
    
    FOR i := 1 TO seg1Len DO
        ch := MID(seg1, 1, i);
        IF (ch < '0') OR (ch > '9') THEN
            valid := TRUE;
        END_IF;
    END_FOR;
    
    IF NOT valid THEN
        FOR i := 1 TO seg2Len DO
            ch := MID(seg2, 1, i);
            IF (ch < '0') OR (ch > '9') THEN
                valid := TRUE;
            END_IF;
        END_FOR;
    END_IF;
    
    IF NOT valid THEN
        FOR i := 1 TO seg3Len DO
            ch := MID(seg3, 1, i);
            IF (ch < '0') OR (ch > '9') THEN
                valid := TRUE;
            END_IF;
        END_FOR;
    END_IF;
    
    IF NOT valid THEN
        FOR i := 1 TO seg4Len DO
            ch := MID(seg4, 1, i);
            IF (ch < '0') OR (ch > '9') THEN
                valid := TRUE;
            END_IF;
        END_FOR;
    END_IF;
    
    IF valid THEN
        valid := FALSE;
    END_IF;
END_IF;

IF valid THEN
    IF val1 <= 255 AND val2 <= 255 AND val3 <= 255 AND val4 <= 255 THEN
        result := (val1 * 16#1000000) OR (val2 * 16#10000) OR (val3 * 16#100) OR val4;
    END_IF;
END_IF;

ipValue := result;
END_FUNCTION_BLOCK
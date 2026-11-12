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
    ch : STRING(1);
END_VAR

result := 0;
valid := TRUE;

len := TO_UINT(LEN(ipText));

IF len = 0 OR len > 15 THEN
    valid := FALSE;
END_IF;

IF valid THEN
    dot1 := TO_UINT(FIND(ipText, '.'));
    IF dot1 <= 1 OR dot1 >= 254 THEN
        valid := FALSE;
    END_IF;
END_IF;

IF valid THEN
    dot2 := TO_UINT(FIND(MID(ipText, TO_INT(len - dot1), TO_INT(dot1 + 1)), '.'));
    IF dot2 > 0 THEN
        dot2 := dot2 + dot1;
    END_IF;
END_IF;

IF valid THEN
    dot3 := 0;
    IF dot2 > 0 AND dot2 < 254 THEN
        dot3 := TO_UINT(FIND(MID(ipText, TO_INT(len - dot2), TO_INT(dot2 + 1)), '.'));
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
    
    IF seg1Len < 1 OR seg1Len > 3 OR seg2Len < 1 OR seg2Len > 3 OR seg3Len < 1 OR seg3Len > 3 OR seg4Len < 1 OR seg4Len > 3 THEN
        valid := FALSE;
    END_IF;
END_IF;

IF valid THEN
    seg1 := LEFT(ipText, TO_INT(seg1Len));
    seg2 := MID(ipText, TO_INT(seg2Len), TO_INT(dot1 + 1));
    seg3 := MID(ipText, TO_INT(seg3Len), TO_INT(dot2 + 1));
    seg4 := RIGHT(ipText, TO_INT(seg4Len));
    
    IF TO_UINT(LEN(seg1)) <> seg1Len OR TO_UINT(LEN(seg2)) <> seg2Len OR
       TO_UINT(LEN(seg3)) <> seg3Len OR TO_UINT(LEN(seg4)) <> seg4Len THEN
        valid := FALSE;
    END_IF;
END_IF;

IF valid THEN
    val1 := STRING_TO_UDINT(seg1);
    val2 := STRING_TO_UDINT(seg2);
    val3 := STRING_TO_UDINT(seg3);
    val4 := STRING_TO_UDINT(seg4);
    
    FOR i := 1 TO TO_INT(seg1Len) DO
        ch := MID(seg1, 1, TO_INT(i));
        IF ch < '0' OR ch > '9' THEN
            valid := FALSE;
        END_IF;
    END_FOR;
    
    FOR i := 1 TO TO_INT(seg2Len) DO
        ch := MID(seg2, 1, TO_INT(i));
        IF ch < '0' OR ch > '9' THEN
            valid := FALSE;
        END_IF;
    END_FOR;
    
    FOR i := 1 TO TO_INT(seg3Len) DO
        ch := MID(seg3, 1, TO_INT(i));
        IF ch < '0' OR ch > '9' THEN
            valid := FALSE;
        END_IF;
    END_FOR;
    
    FOR i := 1 TO TO_INT(seg4Len) DO
        ch := MID(seg4, 1, TO_INT(i));
        IF ch < '0' OR ch > '9' THEN
            valid := FALSE;
        END_IF;
    END_FOR;
END_IF;

IF valid THEN
    IF val1 <= 255 AND val2 <= 255 AND val3 <= 255 AND val4 <= 255 THEN
        result := (val1 * 16#1000000) OR (val2 * 16#10000) OR (val3 * 16#100) OR val4;
    END_IF;
END_IF;

ipValue := result;
END_FUNCTION_BLOCK
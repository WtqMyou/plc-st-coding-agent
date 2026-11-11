FUNCTION_BLOCK FB
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    txtLen : INT;
    idx : INT;
    ch : STRING(1);
    segCount : INT;
    segValue : UDINT;
    segDigits : INT;
    valid : BOOL;
    addrBytes : ARRAY[0..3] OF UDINT;
    digitVal : INT;
    segHasLeadingZero : BOOL;
END_VAR

ipValue := 0;
txtLen := LEN(ipText);
IF txtLen < 7 OR txtLen > 15 THEN
    RETURN;
END_IF;

segCount := 0;
segValue := 0;
segDigits := 0;
valid := TRUE;
segHasLeadingZero := FALSE;
addrBytes[0] := 0;
addrBytes[1] := 0;
addrBytes[2] := 0;
addrBytes[3] := 0;

FOR idx := 1 TO txtLen DO
    ch := MID(ipText, 1, idx);
    IF ch = '.' THEN
        IF (segDigits = 0) OR (segCount >= 3) THEN
            valid := FALSE;
            EXIT;
        END_IF;
        addrBytes[segCount] := segValue;
        segCount := segCount + 1;
        segValue := 0;
        segDigits := 0;
        segHasLeadingZero := FALSE;
    ELSE
        IF ch = '0' THEN
            digitVal := 0;
        ELSIF ch = '1' THEN
            digitVal := 1;
        ELSIF ch = '2' THEN
            digitVal := 2;
        ELSIF ch = '3' THEN
            digitVal := 3;
        ELSIF ch = '4' THEN
            digitVal := 4;
        ELSIF ch = '5' THEN
            digitVal := 5;
        ELSIF ch = '6' THEN
            digitVal := 6;
        ELSIF ch = '7' THEN
            digitVal := 7;
        ELSIF ch = '8' THEN
            digitVal := 8;
        ELSIF ch = '9' THEN
            digitVal := 9;
        ELSE
            valid := FALSE;
            EXIT;
        END_IF;

        IF segDigits = 0 THEN
            IF digitVal = 0 THEN
                segHasLeadingZero := TRUE;
            ELSE
                segHasLeadingZero := FALSE;
            END_IF;
        ELSE
            IF segHasLeadingZero THEN
                valid := FALSE;
                EXIT;
            END_IF;
        END_IF;

        segValue := segValue * 10 + digitVal;
        IF segValue > 255 THEN
            valid := FALSE;
            EXIT;
        END_IF;

        segDigits := segDigits + 1;
        IF segDigits > 3 THEN
            valid := FALSE;
            EXIT;
        END_IF;
    END_IF;
END_FOR;

IF valid THEN
    IF segDigits = 0 THEN
        valid := FALSE;
    ELSE
        addrBytes[segCount] := segValue;
        segCount := segCount + 1;
    END_IF;
END_IF;

IF valid AND (segCount = 4) THEN
    ipValue := SHL(addrBytes[0], 24) OR SHL(addrBytes[1], 16) OR SHL(addrBytes[2], 8) OR addrBytes[3];
ELSE
    ipValue := 0;
END_IF;

END_FUNCTION_BLOCK
FUNCTION_BLOCK FB_IPv4Parser
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    i : INT;
    len : INT;
    octets : ARRAY[1..4] OF UDINT;
    curVal : UDINT;
    digitCount : INT;
    segIndex : INT;
    invalid : BOOL;
    ch : BYTE;
    digit : UDINT;
END_VAR

ipValue := 0;
invalid := FALSE;
segIndex := 1;
curVal := 0;
digitCount := 0;

FOR i := 1 TO 4 DO
    octets[i] := 0;
END_FOR;

len := LEN(ipText);

FOR i := 1 TO len DO
    ch := ipText[i];
    IF (ch >= BYTE#48) AND (ch <= BYTE#57) THEN
        digit := ch - BYTE#48;
        IF NOT invalid THEN
            IF (curVal * 10 + digit) <= 255 THEN
                curVal := curVal * 10 + digit;
                digitCount := digitCount + 1;
            ELSE
                invalid := TRUE;
            END_IF;
        END_IF;
    ELSIF ch = BYTE#46 THEN
        IF NOT invalid THEN
            IF (digitCount > 0) AND (segIndex <= 4) THEN
                octets[segIndex] := curVal;
                segIndex := segIndex + 1;
                curVal := 0;
                digitCount := 0;
            ELSE
                invalid := TRUE;
            END_IF;
        END_IF;
    ELSE
        invalid := TRUE;
    END_IF;
END_FOR;

IF NOT invalid THEN
    IF (digitCount > 0) AND (segIndex <= 4) THEN
        octets[segIndex] := curVal;
        segIndex := segIndex + 1;
    ELSIF (digitCount > 0) AND (segIndex > 4) THEN
        invalid := TRUE;
    ELSIF (digitCount = 0) THEN
        invalid := TRUE;
    END_IF;
END_IF;

IF (NOT invalid) AND (segIndex = 5) THEN
    ipValue := (octets[1] * 16777216) + (octets[2] * 65536) + (octets[3] * 256) + octets[4];
END_IF;

END_FUNCTION_BLOCK
FUNCTION_BLOCK FB
VAR_INPUT
    ipText : STRING(254);
END_VAR

VAR_OUTPUT
    ipValue : UDINT;
END_VAR

VAR
    segmentCount : USINT;
    charIndex : INT;
    charText : STRING(1);
    segmentValue : UDINT;
    digitValue : UDINT;
    parsedAddress : UDINT;
    segmentHasDigit : BOOL;
    invalidInput : BOOL;
END_VAR

ipValue := 0;
segmentCount := 0;
segmentValue := 0;
digitValue := 0;
parsedAddress := 0;
segmentHasDigit := FALSE;
invalidInput := FALSE;

FOR charIndex := 1 TO LEN(ipText) DO
    charText := MID(ipText, 1, charIndex);

    IF charText = '.' THEN
        IF NOT segmentHasDigit THEN
            invalidInput := TRUE;
        END_IF;

        IF segmentCount >= 3 THEN
            invalidInput := TRUE;
        END_IF;

        IF NOT invalidInput THEN
            parsedAddress := parsedAddress * 256 + segmentValue;
            segmentCount := segmentCount + 1;
            segmentValue := 0;
            segmentHasDigit := FALSE;
        END_IF;
    ELSE
        IF charText = '0' THEN
            digitValue := 0;
        ELSIF charText = '1' THEN
            digitValue := 1;
        ELSIF charText = '2' THEN
            digitValue := 2;
        ELSIF charText = '3' THEN
            digitValue := 3;
        ELSIF charText = '4' THEN
            digitValue := 4;
        ELSIF charText = '5' THEN
            digitValue := 5;
        ELSIF charText = '6' THEN
            digitValue := 6;
        ELSIF charText = '7' THEN
            digitValue := 7;
        ELSIF charText = '8' THEN
            digitValue := 8;
        ELSIF charText = '9' THEN
            digitValue := 9;
        ELSE
            invalidInput := TRUE;
        END_IF;

        IF NOT invalidInput THEN
            IF segmentHasDigit AND segmentValue = 0 THEN
                invalidInput := TRUE;
            END_IF;
        END_IF;

        IF NOT invalidInput THEN
            IF segmentValue > 25 OR (segmentValue = 25 AND digitValue > 5) THEN
                invalidInput := TRUE;
            END_IF;
        END_IF;

        IF NOT invalidInput THEN
            segmentValue := segmentValue * 10 + digitValue;
            segmentHasDigit := TRUE;
        END_IF;
    END_IF;

    IF invalidInput THEN
        EXIT;
    END_IF;
END_FOR;

IF NOT invalidInput AND segmentHasDigit AND segmentCount = 3 THEN
    parsedAddress := parsedAddress * 256 + segmentValue;
    ipValue := parsedAddress;
END_IF;
END_FUNCTION_BLOCK
FUNCTION_BLOCK IPv4_Parser
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    len           : INT;
    i             : INT;
    charStr       : STRING(1);
    digitValue    : INT;
    isDigit       : BOOL;
    dotCount      : INT;
    segmentDigits : INT;
    octet         : UDINT;
    assembled     : UDINT;
    valid         : BOOL;
END_VAR

ipValue := 0;
valid := TRUE;
len := LEN(ipText);

// A valid IPv4 text has at least 7 characters ("0.0.0.0")
// and at most 15 characters ("255.255.255.255").
IF (len < 7) OR (len > 15) THEN
    valid := FALSE;
END_IF;

assembled := 0;
octet := 0;
dotCount := 0;
segmentDigits := 0;
i := 1;

WHILE (i <= len) AND valid DO
    // Extract one character as a string
    charStr := MID(ipText, i, 1);
    isDigit := FALSE;
    digitValue := 0;

    // Check if charStr is a decimal digit
    CASE charStr OF
        '0': digitValue := 0; isDigit := TRUE;
        '1': digitValue := 1; isDigit := TRUE;
        '2': digitValue := 2; isDigit := TRUE;
        '3': digitValue := 3; isDigit := TRUE;
        '4': digitValue := 4; isDigit := TRUE;
        '5': digitValue := 5; isDigit := TRUE;
        '6': digitValue := 6; isDigit := TRUE;
        '7': digitValue := 7; isDigit := TRUE;
        '8': digitValue := 8; isDigit := TRUE;
        '9': digitValue := 9; isDigit := TRUE;
    END_CASE;

    IF isDigit THEN
        // Decimal digit
        segmentDigits := segmentDigits + 1;
        octet := (octet * 10) + digitValue;

        IF octet > 255 THEN
            valid := FALSE;
        END_IF;

    ELSIF charStr = '.' THEN
        // Period separator
        IF segmentDigits = 0 THEN
            valid := FALSE; // Empty segment
        ELSE
            assembled := (assembled * 256) + octet;
            octet := 0;
            segmentDigits := 0;
            dotCount := dotCount + 1;

            IF dotCount > 3 THEN
                valid := FALSE; // Too many segments
            END_IF;
        END_IF;

    ELSE
        // Any other character is invalid
        valid := FALSE;
    END_IF;

    i := i + 1;
END_WHILE;

IF valid THEN
    IF segmentDigits = 0 THEN
        valid := FALSE; // Trailing dot or missing final segment
    ELSIF octet > 255 THEN
        valid := FALSE;
    ELSIF dotCount <> 3 THEN
        valid := FALSE; // Incorrect segment count
    ELSE
        assembled := (assembled * 256) + octet;
        ipValue := assembled;
    END_IF;
END_IF;

END_FUNCTION_BLOCK
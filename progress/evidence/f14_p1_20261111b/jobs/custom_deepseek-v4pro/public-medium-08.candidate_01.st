FUNCTION_BLOCK IPv4_Parser
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    len          : INT;
    i            : INT;
    ch           : INT;
    dotCount     : INT;
    segmentDigits: INT;
    octet        : UDINT;
    assembled    : UDINT;
    valid        : BOOL;
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
    ch := ipText[i];

    IF (ch >= 48) AND (ch <= 57) THEN
        // Decimal digit
        segmentDigits := segmentDigits + 1;
        octet := (octet * 10) + (ch - 48);

        IF octet > 255 THEN
            valid := FALSE;
        END_IF;

    ELSIF ch = 46 THEN
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
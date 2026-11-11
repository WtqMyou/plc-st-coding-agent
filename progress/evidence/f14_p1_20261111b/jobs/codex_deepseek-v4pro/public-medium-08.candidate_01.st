FUNCTION_BLOCK IPv4Parser
VAR_INPUT
    ipText : STRING(254);
END_VAR

VAR_OUTPUT
    ipValue : UDINT;
END_VAR

VAR
    index        : DINT;
    textLen      : DINT;
    dotCount     : DINT;
    currentByte  : BYTE;
    segmentValue : UDINT;
    inSegment    : BOOL;
    segments     : ARRAY[1..4] OF UDINT;
    digitValue   : UDINT;
END_VAR

ipValue := 0;
textLen := LEN(ipText);

IF textLen = 0 THEN
    RETURN;
END_IF;

dotCount := 0;
segmentValue := 0;
inSegment := FALSE;

FOR index := 1 TO textLen DO
    currentByte := ipText[index];

    IF currentByte = 46 THEN
        IF NOT inSegment OR dotCount >= 3 THEN
            RETURN;
        END_IF;

        IF segmentValue > 255 THEN
            RETURN;
        END_IF;

        segments[dotCount + 1] := segmentValue;
        dotCount := dotCount + 1;
        segmentValue := 0;
        inSegment := FALSE;
    ELSIF currentByte >= 48 AND currentByte <= 57 THEN
        IF currentByte = 48 THEN
            digitValue := 0;
        ELSIF currentByte = 49 THEN
            digitValue := 1;
        ELSIF currentByte = 50 THEN
            digitValue := 2;
        ELSIF currentByte = 51 THEN
            digitValue := 3;
        ELSIF currentByte = 52 THEN
            digitValue := 4;
        ELSIF currentByte = 53 THEN
            digitValue := 5;
        ELSIF currentByte = 54 THEN
            digitValue := 6;
        ELSIF currentByte = 55 THEN
            digitValue := 7;
        ELSIF currentByte = 56 THEN
            digitValue := 8;
        ELSE
            digitValue := 9;
        END_IF;

        IF segmentValue > 255 THEN
            RETURN;
        END_IF;

        segmentValue := segmentValue * 10 + digitValue;

        IF segmentValue > 255 THEN
            RETURN;
        END_IF;

        inSegment := TRUE;
    ELSE
        RETURN;
    END_IF;
END_FOR;

IF NOT inSegment OR dotCount <> 3 THEN
    RETURN;
END_IF;

segments[4] := segmentValue;

ipValue := segments[1] * 16777216
         + segments[2] * 65536
         + segments[3] * 256
         + segments[4];

END_FUNCTION_BLOCK
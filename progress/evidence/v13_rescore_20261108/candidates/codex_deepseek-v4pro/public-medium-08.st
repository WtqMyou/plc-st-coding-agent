FUNCTION_BLOCK FB
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    scanIndex : INT;
    currentChar : STRING(1);
    currentSegment : UDINT;
    digitValue : UDINT;
    segmentCount : INT;
    hasDigit : BOOL;
    isValid : BOOL;
    ok : BOOL;
END_VAR

ipValue := UDINT#0;
currentSegment := UDINT#0;
segmentCount := 0;
hasDigit := FALSE;
isValid := TRUE;

FOR scanIndex := 1 TO LEN(ipText) BY 1 DO
    IF isValid THEN
        currentChar := MID(ipText, 1, scanIndex);

        IF currentChar = '.' THEN
            IF hasDigit THEN
                segmentCount := segmentCount + 1;
                ipValue := (ipValue * UDINT#256) + currentSegment;
                currentSegment := UDINT#0;
                hasDigit := FALSE;
            ELSE
                isValid := FALSE;
            END_IF
        ELSIF currentChar = '0' THEN
            digitValue := UDINT#0;
            hasDigit := TRUE;
            currentSegment := (currentSegment * UDINT#10) + digitValue;
            IF currentSegment > UDINT#255 THEN
                isValid := FALSE;
            END_IF
        ELSIF currentChar = '1' THEN
            digitValue := UDINT#1;
            hasDigit := TRUE;
            currentSegment := (currentSegment * UDINT#10) + digitValue;
            IF currentSegment > UDINT#255 THEN
                isValid := FALSE;
            END_IF
        ELSIF currentChar = '2' THEN
            digitValue := UDINT#2;
            hasDigit := TRUE;
            currentSegment := (currentSegment * UDINT#10) + digitValue;
            IF currentSegment > UDINT#255 THEN
                isValid := FALSE;
            END_IF
        ELSIF currentChar = '3' THEN
            digitValue := UDINT#3;
            hasDigit := TRUE;
            currentSegment := (currentSegment * UDINT#10) + digitValue;
            IF currentSegment > UDINT#255 THEN
                isValid := FALSE;
            END_IF
        ELSIF currentChar = '4' THEN
            digitValue := UDINT#4;
            hasDigit := TRUE;
            currentSegment := (currentSegment * UDINT#10) + digitValue;
            IF currentSegment > UDINT#255 THEN
                isValid := FALSE;
            END_IF
        ELSIF currentChar = '5' THEN
            digitValue := UDINT#5;
            hasDigit := TRUE;
            currentSegment := (currentSegment * UDINT#10) + digitValue;
            IF currentSegment > UDINT#255 THEN
                isValid := FALSE;
            END_IF
        ELSIF currentChar = '6' THEN
            digitValue := UDINT#6;
            hasDigit := TRUE;
            currentSegment := (currentSegment * UDINT#10) + digitValue;
            IF currentSegment > UDINT#255 THEN
                isValid := FALSE;
            END_IF
        ELSIF currentChar = '7' THEN
            digitValue := UDINT#7;
            hasDigit := TRUE;
            currentSegment := (currentSegment * UDINT#10) + digitValue;
            IF currentSegment > UDINT#255 THEN
                isValid := FALSE;
            END_IF
        ELSIF currentChar = '8' THEN
            digitValue := UDINT#8;
            hasDigit := TRUE;
            currentSegment := (currentSegment * UDINT#10) + digitValue;
            IF currentSegment > UDINT#255 THEN
                isValid := FALSE;
            END_IF
        ELSIF currentChar = '9' THEN
            digitValue := UDINT#9;
            hasDigit := TRUE;
            currentSegment := (currentSegment * UDINT#10) + digitValue;
            IF currentSegment > UDINT#255 THEN
                isValid := FALSE;
            END_IF
        ELSE
            isValid := FALSE;
        END_IF
    END_IF
END_FOR

IF isValid THEN
    IF hasDigit THEN
        segmentCount := segmentCount + 1;
        ipValue := (ipValue * UDINT#256) + currentSegment;
    ELSE
        isValid := FALSE;
    END_IF
END_IF

IF isValid AND (segmentCount <> 4) THEN
    isValid := FALSE;
END_IF

IF isValid THEN
    ok := TRUE;
ELSE
    ipValue := UDINT#0;
    ok := FALSE;
END_IF

END_FUNCTION_BLOCK
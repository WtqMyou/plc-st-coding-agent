FUNCTION_BLOCK FB
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    charText : STRING(1);
    textLength : INT;
    textPosition : INT;
    segmentCount : INT;
    segmentLength : INT;
    segmentDigit : UDINT;
    segmentValue : UDINT;
    segmentStartsZero : BOOL;
    digitMatched : BOOL;
    validText : BOOL;
    segmentValues : ARRAY[1..4] OF UDINT;
END_VAR

ipValue := UDINT#0;
validText := TRUE;
textLength := LEN(ipText);
textPosition := 1;
segmentCount := 0;
segmentLength := 0;
segmentValue := UDINT#0;
segmentStartsZero := FALSE;

IF (textLength < 7) OR (textLength > 15) THEN
    validText := FALSE;
END_IF

WHILE validText AND (textPosition <= textLength) DO
    charText := MID(ipText, 1, textPosition);

    IF charText = '.' THEN
        IF (segmentLength = 0) OR (segmentCount >= 3) THEN
            validText := FALSE;
        ELSE
            segmentCount := segmentCount + 1;
            segmentValues[segmentCount] := segmentValue;
            segmentValue := UDINT#0;
            segmentLength := 0;
            segmentStartsZero := FALSE;
        END_IF
    ELSE
        digitMatched := FALSE;
        segmentDigit := UDINT#0;

        IF charText = '0' THEN
            segmentDigit := UDINT#0;
            digitMatched := TRUE;
        ELSIF charText = '1' THEN
            segmentDigit := UDINT#1;
            digitMatched := TRUE;
        ELSIF charText = '2' THEN
            segmentDigit := UDINT#2;
            digitMatched := TRUE;
        ELSIF charText = '3' THEN
            segmentDigit := UDINT#3;
            digitMatched := TRUE;
        ELSIF charText = '4' THEN
            segmentDigit := UDINT#4;
            digitMatched := TRUE;
        ELSIF charText = '5' THEN
            segmentDigit := UDINT#5;
            digitMatched := TRUE;
        ELSIF charText = '6' THEN
            segmentDigit := UDINT#6;
            digitMatched := TRUE;
        ELSIF charText = '7' THEN
            segmentDigit := UDINT#7;
            digitMatched := TRUE;
        ELSIF charText = '8' THEN
            segmentDigit := UDINT#8;
            digitMatched := TRUE;
        ELSIF charText = '9' THEN
            segmentDigit := UDINT#9;
            digitMatched := TRUE;
        END_IF

        IF digitMatched THEN
            IF (segmentLength > 0) AND segmentStartsZero THEN
                validText := FALSE;
            ELSE
                segmentLength := segmentLength + 1;

                IF segmentLength = 1 THEN
                    segmentStartsZero := (segmentDigit = UDINT#0);
                END_IF

                segmentValue := segmentValue * UDINT#10 + segmentDigit;

                IF segmentValue > UDINT#255 THEN
                    validText := FALSE;
                END_IF
            END_IF
        ELSE
            validText := FALSE;
        END_IF
    END_IF

    textPosition := textPosition + 1;
END_WHILE

IF validText THEN
    IF (segmentLength = 0) OR (segmentCount <> 3) THEN
        validText := FALSE;
    ELSE
        segmentValues[4] := segmentValue;
    END_IF
END_IF

IF validText THEN
    ipValue := (segmentValues[1] * UDINT#16777216)
             + (segmentValues[2] * UDINT#65536)
             + (segmentValues[3] * UDINT#256)
             + segmentValues[4];
END_IF

END_FUNCTION_BLOCK
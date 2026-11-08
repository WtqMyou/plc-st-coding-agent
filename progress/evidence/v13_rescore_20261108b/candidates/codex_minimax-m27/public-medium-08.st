FUNCTION_BLOCK FB
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    idx : INT;
    segCount : INT;
    curSeg : UDINT;
    result : UDINT;
    digitFound : BOOL;
    shiftBits : INT;
    tempChar : STRING(1);
    inputValid : BOOL;
END_VAR

ipValue := 0;
idx := 1;
segCount := 0;
curSeg := 0;
result := 0;
digitFound := FALSE;
inputValid := TRUE;

WHILE idx <= LEN(ipText) AND inputValid DO
    tempChar := MID(ipText, 1, idx);
    
    IF tempChar = '.' THEN
        IF NOT digitFound OR curSeg > 255 THEN
            inputValid := FALSE;
        ELSE
            segCount := segCount + 1;
            shiftBits := (4 - segCount) * 8;
            result := result OR SHL(curSeg, shiftBits);
            curSeg := 0;
            digitFound := FALSE;
        END_IF
    ELSIF tempChar >= '0' AND tempChar <= '9' THEN
        digitFound := TRUE;
        curSeg := curSeg * 10 + (MID(ipText, 1, idx) - '0');
        IF curSeg > 255 THEN
            inputValid := FALSE;
        END_IF
    ELSE
        inputValid := FALSE;
    END_IF
    
    idx := idx + 1;
END_WHILE

IF inputValid AND digitFound AND curSeg <= 255 THEN
    segCount := segCount + 1;
    shiftBits := (4 - segCount) * 8;
    result := result OR SHL(curSeg, shiftBits);
    
    IF segCount = 4 THEN
        ipValue := result;
    END_IF;
END_IF;
END_FUNCTION_BLOCK
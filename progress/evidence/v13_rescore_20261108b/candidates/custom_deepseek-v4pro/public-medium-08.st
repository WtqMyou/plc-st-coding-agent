FUNCTION_BLOCK FB
VAR_INPUT
    ipText : STRING(254);
END_VAR
VAR_OUTPUT
    ipValue : UDINT;
END_VAR
VAR
    ok : BOOL := FALSE;
    segCount : INT := 0;
    segLen : INT;
    segVal : UDINT;
    segIndex : INT;
    segVals : ARRAY[1..4] OF UDINT;
    textLen : INT;
    i : INT;
    ch : STRING(1);
END_VAR

// 初始化
ok := TRUE;
ipValue := 0;
segCount := 0;
segIndex := 1;
segLen := 0;
segVal := 0;
textLen := LEN(ipText);

FOR i := 1 TO textLen DO
    ch := MID(ipText, i, 1);
    IF ch = '.' THEN
        // 点：结束当前段
        IF segLen = 0 THEN
            ok := FALSE;
            EXIT;
        END_IF;
        IF segVal > 255 THEN
            ok := FALSE;
            EXIT;
        END_IF;
        IF segIndex > 4 THEN
            ok := FALSE;
            EXIT;
        END_IF;
        segVals[segIndex] := segVal;
        segIndex := segIndex + 1;
        // 重置当前段
        segVal := 0;
        segLen := 0;
    ELSIF ch = '0' THEN
        segVal := segVal * 10 + 0;
        segLen := segLen + 1;
    ELSIF ch = '1' THEN
        segVal := segVal * 10 + 1;
        segLen := segLen + 1;
    ELSIF ch = '2' THEN
        segVal := segVal * 10 + 2;
        segLen := segLen + 1;
    ELSIF ch = '3' THEN
        segVal := segVal * 10 + 3;
        segLen := segLen + 1;
    ELSIF ch = '4' THEN
        segVal := segVal * 10 + 4;
        segLen := segLen + 1;
    ELSIF ch = '5' THEN
        segVal := segVal * 10 + 5;
        segLen := segLen + 1;
    ELSIF ch = '6' THEN
        segVal := segVal * 10 + 6;
        segLen := segLen + 1;
    ELSIF ch = '7' THEN
        segVal := segVal * 10 + 7;
        segLen := segLen + 1;
    ELSIF ch = '8' THEN
        segVal := segVal * 10 + 8;
        segLen := segLen + 1;
    ELSIF ch = '9' THEN
        segVal := segVal * 10 + 9;
        segLen := segLen + 1;
    ELSE
        ok := FALSE;
        EXIT;
    END_IF;
END_FOR;

// 处理最后一个段
IF ok THEN
    IF segLen = 0 THEN
        ok := FALSE;
    ELSIF segVal > 255 THEN
        ok := FALSE;
    ELSIF segIndex > 4 THEN
        ok := FALSE;
    ELSE
        segVals[segIndex] := segVal;
        segIndex := segIndex + 1;
    END_IF;
END_IF;

// 最终判断
IF ok AND (segIndex - 1 = 4) THEN
    segCount := 4;
    ipValue := SHL(segVals[1], 24) OR SHL(segVals[2], 16) OR SHL(segVals[3], 8) OR segVals[4];
ELSE
    ok := FALSE;
    segCount := 0;
    ipValue := 0;
END_IF;

END_FUNCTION_BLOCK
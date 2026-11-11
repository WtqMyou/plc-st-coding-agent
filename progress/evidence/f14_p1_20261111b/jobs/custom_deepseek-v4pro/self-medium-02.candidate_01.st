FUNCTION_BLOCK FB
VAR_INPUT
    enable : BOOL;
    rawValue : REAL;
END_VAR
VAR_OUTPUT
    filteredValue : REAL;
    windowFull : BOOL;
    sampleCount : INT;
END_VAR
VAR
    buffer : ARRAY[0..7] OF REAL;
    count : INT := 0;
    sum : REAL;
    i : INT;
END_VAR

IF enable THEN
    // 更新缓冲区
    IF count < 8 THEN
        buffer[count] := rawValue;
        count := count + 1;
    ELSE
        // 满窗，FIFO左移
        FOR i := 0 TO 6 DO
            buffer[i] := buffer[i+1];
        END_FOR;
        buffer[7] := rawValue;
    END_IF;

    // 计算平均值
    sum := 0.0;
    FOR i := 0 TO count-1 DO
        sum := sum + buffer[i];
    END_FOR;
    filteredValue := sum / INT_TO_REAL(count);
ELSE
    // 停用：清空计数，保持filteredValue
    count := 0;
END_IF;

// 更新输出计数和满标志
sampleCount := count;
windowFull := (count = 8);
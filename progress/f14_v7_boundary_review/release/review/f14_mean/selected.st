FUNCTION_BLOCK FB
VAR_INPUT
    cyclicExecution : BOOL;
    trigger : BOOL;
    value : LREAL;
    windowSize : INT;
    reset : BOOL;
END_VAR
VAR_OUTPUT
    average : LREAL;
    windowSizeReached : BOOL;
    error : BOOL;
    status : WORD;
END_VAR
VAR
    buffer : ARRAY [0..99] OF LREAL;
    count : INT := 0;
    writeIndex : INT := 0;
    lastTrigger : BOOL := FALSE;
    rising : BOOL;
    sum : LREAL;
    i : INT;
    startIndex : INT;
    validRead : BOOL;
    firstScan : BOOL := TRUE;
END_VAR

// 首次扫描初始化
IF firstScan THEN
    count := 0;
    writeIndex := 0;
    average := 0.0;
    windowSizeReached := FALSE;
    firstScan := FALSE;
END_IF

// 计算 trigger 上升沿
rising := trigger AND NOT lastTrigger;

// 设置错误状态与状态码
IF (windowSize < 1) OR (windowSize > 100) THEN
    error := TRUE;
    status := 16#8200;
ELSE
    error := FALSE;
    status := 16#0000;
END_IF

// 复位处理（优先级高于读取）
IF reset THEN
    count := 0;
    writeIndex := 0;
    average := 0.0;
    windowSizeReached := FALSE;
    lastTrigger := trigger;  // 防止复位解除后当前高电平被误判为上升沿
ELSE
    // 判断是否有读取请求
    IF cyclicExecution THEN
        validRead := TRUE;
    ELSE
        validRead := rising;
    END_IF

    IF validRead THEN
        // 仅在窗口合法时更新
        IF NOT error THEN
            // 窗口缩小可能使 count 大于 windowSize，截断至窗口大小
            IF count > windowSize THEN
                count := windowSize;
            END_IF

            // 写入新样本（环形缓冲区）
            buffer[writeIndex] := value;
            writeIndex := (writeIndex + 1) MOD 100;
            IF count < windowSize THEN
                count := count + 1;
            END_IF

            // 计算移动平均
            IF count > 0 THEN
                sum := 0.0;
                startIndex := (writeIndex - count + 100) MOD 100;
                FOR i := 0 TO count - 1 DO
                    sum := sum + buffer[(startIndex + i) MOD 100];
                END_FOR
                average := sum / INT_TO_LREAL(count);
            ELSE
                average := 0.0;
            END_IF

            // 设置窗口满标志
            IF count >= windowSize THEN
                windowSizeReached := TRUE;
            ELSE
                windowSizeReached := FALSE;
            END_IF
        END_IF
    END_IF
END_IF

// 更新 lastTrigger（对所有情况执行，复位分支已设置相同值，此处保持一致性）
lastTrigger := trigger;

END_FUNCTION_BLOCK
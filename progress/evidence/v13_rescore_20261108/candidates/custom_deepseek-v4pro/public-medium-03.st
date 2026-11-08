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
    buffer : ARRAY[0..99] OF LREAL;
    inIdx : INT := 0;
    outIdx : INT := 0;
    count : INT := 0;
    sum : LREAL := 0.0;
    lastTrigger : BOOL := FALSE;
    shouldRead : BOOL;
    oldest : LREAL;
END_VAR

IF reset THEN
    // 复位：清除所有数据状态
    count := 0;
    sum := 0.0;
    inIdx := 0;
    outIdx := 0;
    average := 0.0;
    windowSizeReached := FALSE;
    // 检查窗口尺寸并设置错误状态
    IF windowSize < 1 OR windowSize > 100 THEN
        error := TRUE;
        status := 16#8200;
    ELSE
        error := FALSE;
        status := 16#0000;
    END_IF;
    // 更新触发边沿记忆
    lastTrigger := trigger;
ELSE
    // 检查窗口尺寸有效性
    IF windowSize < 1 OR windowSize > 100 THEN
        error := TRUE;
        status := 16#8200;
        average := 0.0;
        windowSizeReached := FALSE;
        lastTrigger := trigger;
    ELSE
        error := FALSE;
        status := 16#0000;
        
        // 调整缓冲区大小：如果当前样本数大于窗口尺寸，移除最旧的样本
        WHILE count > windowSize DO
            oldest := buffer[outIdx];
            sum := sum - oldest;
            outIdx := outIdx + 1;
            IF outIdx >= 100 THEN
                outIdx := 0;
            END_IF;
            count := count - 1;
        END_WHILE;
        
        // 确定是否应读取新值
        shouldRead := cyclicExecution OR (trigger AND NOT lastTrigger);
        
        // 更新触发边沿记忆
        lastTrigger := trigger;
        
        IF shouldRead THEN
            // 写入新值到缓冲区
            buffer[inIdx] := value;
            inIdx := inIdx + 1;
            IF inIdx >= 100 THEN
                inIdx := 0;
            END_IF;
            
            IF count = windowSize THEN
                // 缓冲区已满：移除最旧样本
                oldest := buffer[outIdx];
                sum := sum - oldest;
                outIdx := outIdx + 1;
                IF outIdx >= 100 THEN
                    outIdx := 0;
                END_IF;
                // count 保持不变
            ELSE
                // 缓冲区未满：增加样本计数
                count := count + 1;
            END_IF;
            
            // 更新总和
            sum := sum + value;
        END_IF;
        
        // 计算移动平均
        IF count > 0 THEN
            average := sum / count;
        ELSE
            average := 0.0;
        END_IF;
        
        // 窗口是否已满
        windowSizeReached := (count >= windowSize);
    END_IF;
END_IF;

END_FUNCTION_BLOCK
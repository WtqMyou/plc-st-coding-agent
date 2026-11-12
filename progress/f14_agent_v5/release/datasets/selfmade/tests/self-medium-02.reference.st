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
    buf : ARRAY[1..8] OF REAL;
    wr : INT;
    i : INT;
    sum : REAL;
    keep : REAL;
END_VAR

(* 关断时清空历史，但输出保持最后一次的有效值 *)
IF NOT enable THEN
    FOR i := 1 TO 8 DO
        buf[i] := 0.0;
    END_FOR
    wr := 0;
    sampleCount := 0;
    windowFull := FALSE;
ELSE
    (* 环形缓冲：wr 指向最老元素，写进去就等于淘汰最老的那个 *)
    wr := wr + 1;
    IF wr > 8 THEN
        wr := 1;
    END_IF
    buf[wr] := rawValue;
    IF sampleCount < 8 THEN
        sampleCount := sampleCount + 1;
    END_IF
    windowFull := sampleCount >= 8;

    (* 只对**实际已有**的样本求平均，未满时不得按 0 填充 *)
    sum := 0.0;
    FOR i := 1 TO sampleCount DO
        sum := sum + buf[i];
    END_FOR
    keep := sum / INT_TO_REAL(sampleCount);
END_IF
(* 每一拍都从静态变量刷新输出：输出变量本身不记忆，靠 keep 记忆 *)
filteredValue := keep;
END_FUNCTION_BLOCK

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
    buf : ARRAY[1..100] OF LREAL;
    cnt : INT;
    head : INT;
    prevTrigger : BOOL;
    trigEdge : BOOL;
    n : INT;
    i : INT;
    idx : INT;
    sum : LREAL;
    take : BOOL;
END_VAR

(* R2: 外部触发只取上升沿；周期模式与触发模式共用同一个采样标志 *)
trigEdge := trigger AND NOT prevTrigger;
prevTrigger := trigger;

(* R3: 窗口尺寸校验，16#0000 正常 / 16#8200 窗口长度错误。
   校验不受 reset 影响：尺寸非法时报错优先，避免复位把错误状态掩盖掉 *)
IF windowSize < 1 OR windowSize > 100 THEN
    error := TRUE;
    status := 16#8200;
ELSE
    error := FALSE;
    status := 16#0000;
END_IF

(* R3: 复位清空窗口统计；复位当拍不再采样，避免"清零后立刻又加一个值" *)
IF reset THEN
    cnt := 0;
    average := 0.0;
    windowSizeReached := FALSE;
ELSE
    IF NOT error THEN
        (* R1: 周期模式每扫描周期采样一次，且此模式下 trigger 无效 *)
        take := cyclicExecution OR trigEdge;
        IF take THEN
            head := head + 1;
            IF head > 100 THEN
                head := 1;
            END_IF
            buf[head] := value;
            IF cnt < 100 THEN
                cnt := cnt + 1;
            END_IF
        END_IF

        (* 窗口长度运行时可变：只对最近 n 个样本求均值，FIFO 淘汰最旧样本 *)
        n := cnt;
        IF n > windowSize THEN
            n := windowSize;
        END_IF
        windowSizeReached := cnt >= windowSize;
        IF n > 0 THEN
            sum := 0.0;
            FOR i := 0 TO n - 1 DO
                idx := head - i;
                IF idx < 1 THEN
                    idx := idx + 100;
                END_IF
                sum := sum + buf[idx];
            END_FOR
            average := sum / n;
        END_IF
    END_IF
END_IF
END_FUNCTION_BLOCK

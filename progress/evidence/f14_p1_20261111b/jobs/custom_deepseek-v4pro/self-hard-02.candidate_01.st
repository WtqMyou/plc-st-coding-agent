FUNCTION_BLOCK FB
VAR_INPUT
    startBtn : BOOL;
    abortBtn : BOOL;
    setpoint : REAL;
    pv : REAL;
    maxDuration : INT;
END_VAR
VAR_OUTPUT
    elapsed : INT;
    phase : INT;
    timeout : BOOL;
END_VAR
VAR
    lastStartBtn : BOOL := FALSE;   // 上一拍 startBtn 状态，用于上升沿检测
    prev_phase : INT;               // 上一拍阶段号
    prev_elapsed : INT;             // 上一拍累计拍数
    prev_timeout : BOOL;            // 上一拍超时标志
    rising : BOOL;                  // 本拍 startBtn 上升沿
END_VAR

// ----- 保存上一拍输出 -----
prev_phase := phase;
prev_elapsed := elapsed;
prev_timeout := timeout;

// ----- 检测启动上升沿（包括中止当拍）-----
rising := startBtn AND NOT lastStartBtn;

// ----- 优先级处理：中止 > 新启动沿 > 运行计数 -----
IF abortBtn THEN
    // 中止：立即进入中止态，elapsed 与 timeout 保持上一拍值
    phase := 9;
    // elapsed 不赋值，保持 prev_elapsed
    // timeout 不赋值，保持 prev_timeout
ELSIF rising THEN
    // 新启动沿且未中止：开始新批次，启动拍不计数
    phase := 1;
    elapsed := 0;
    timeout := FALSE;
ELSE
    // 无中止、无新启动沿：运行计数或状态保持
    IF (prev_phase = 1) OR (prev_phase = 2) THEN
        // 上一拍为运行态：累计拍数加 1
        elapsed := prev_elapsed + 1;
        // 判断本拍是否超时（达到或超过 maxDuration）
        IF elapsed >= maxDuration THEN
            // 超时优先于升温达标
            timeout := TRUE;
            phase := 3;
        ELSE
            // 未超时：保持超时标志为 FALSE，处理升温/保温转换
            timeout := FALSE;
            IF prev_phase = 2 THEN
                // 保温阶段维持
                phase := 2;
            ELSIF (prev_phase = 1) AND (pv >= setpoint) THEN
                // 升温达标，进入保温
                phase := 2;
            ELSE
                // 升温且未达标，继续升温
                phase := 1;
            END_IF;
        END_IF;
    ELSE
        // 上一拍非运行态（0,3,9）：完整保持原状态
        phase := prev_phase;
        elapsed := prev_elapsed;
        timeout := prev_timeout;
    END_IF;
END_IF;

// ----- 消耗启动沿：更新 lastStartBtn 为当前 startBtn -----
lastStartBtn := startBtn;
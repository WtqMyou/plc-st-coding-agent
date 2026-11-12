FUNCTION_BLOCK FB
VAR_INPUT
    startBtn : BOOL;
    abortBtn : BOOL;
    setpoint : REAL;
    pv : REAL;
    maxDuration : INT;
END_VAR
VAR_OUTPUT
    elapsed : INT := 0;
    phase : INT := 0;
    timeout : BOOL := FALSE;
END_VAR
VAR
    lastStartBtn : BOOL := FALSE;
    prevPhase : INT := 0;
    prevElapsed : INT := 0;
    prevTimeout : BOOL := FALSE;
    risingStart : BOOL;
END_VAR

// 捕获上一拍输出值
prevPhase := phase;
prevElapsed := elapsed;
prevTimeout := timeout;

// 检测启动上升沿（基于上一拍 lastStartBtn）
risingStart := startBtn AND NOT lastStartBtn;

// 优先级：中止 > 新启动沿 > 运行计数/保持
IF abortBtn THEN
    // 中止：进入9，冻结计数与超时标志
    phase := 9;
    elapsed := prevElapsed;
    timeout := prevTimeout;
ELSIF risingStart THEN
    // 有效新启动：启动拍不计数
    phase := 1;
    elapsed := 0;
    timeout := FALSE;
ELSE
    // 无中止、无新启动沿
    IF (prevPhase = 1) OR (prevPhase = 2) THEN
        // 上一拍运行态，先计数一拍
        elapsed := prevElapsed + 1;

        IF elapsed >= maxDuration THEN
            // 达到超时门槛：完成态3
            timeout := TRUE;
            phase := 3;
        ELSE
            // 未超时，处理升温/保温
            timeout := FALSE;

            IF prevPhase = 1 THEN
                IF pv >= setpoint THEN
                    phase := 2; // 升温达标转保温
                ELSE
                    phase := 1; // 继续升温
                END_IF;
            ELSE
                // prevPhase = 2，保持保温
                phase := 2;
            END_IF;
        END_IF;
    ELSE
        // 上一拍非运行态（0、3、9），保持原状态
        phase := prevPhase;
        elapsed := prevElapsed;
        timeout := prevTimeout;
    END_IF;
END_IF;

// 更新上一拍启动按钮状态
lastStartBtn := startBtn;

END_FUNCTION_BLOCK
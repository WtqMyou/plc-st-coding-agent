FUNCTION_BLOCK FB
VAR_INPUT
    startBtn   : BOOL;
    resetBtn   : BOOL;
    doneSensor : BOOL;
    targetVol  : REAL;
    flowVol    : REAL;
END_VAR
VAR_OUTPUT
    valveOpen  : BOOL;
    fillsToday : INT;
END_VAR
VAR
    prev_startBtn   : BOOL := FALSE;
    prev_resetBtn   : BOOL := FALSE;
    prev_valveOpen  : BOOL := FALSE;
    currentFillVol  : REAL := 0.0;
    pendingConfirm  : BOOL := FALSE;
END_VAR

VAR
    risingStart : BOOL;
    risingReset : BOOL;
END_VAR

// 检测上升沿（基于上周期状态）
risingStart := startBtn AND NOT prev_startBtn;
risingReset := resetBtn  AND NOT prev_resetBtn;

// 复位处理（最高优先级）
IF risingReset THEN
    fillsToday      := 0;
    valveOpen       := FALSE;
    pendingConfirm  := FALSE;
    currentFillVol  := 0.0;
ELSE
    // 非复位时处理
    
    // 启动新瓶
    IF risingStart THEN
        // 取消上一瓶的待确认（如果有）
        pendingConfirm := FALSE;
        // 清零本瓶累计并开阀
        currentFillVol := 0.0;
        valveOpen      := TRUE;
    END_IF;

    // 灌装累计（阀开时）
    IF valveOpen THEN
        currentFillVol := currentFillVol + flowVol;
    END_IF;

    // 达标检测：累计达到或超过目标体积时立即关阀并设待确认
    IF valveOpen AND currentFillVol >= targetVol THEN
        valveOpen      := FALSE;
        pendingConfirm := TRUE;
    END_IF;

    // 确认检测：待确认且传感器为真时确认并计数
    IF pendingConfirm AND doneSensor THEN
        pendingConfirm := FALSE;
        IF fillsToday < 32767 THEN
            fillsToday := fillsToday + 1;
        END_IF;
    END_IF;
END_IF;

// 更新状态变量
prev_startBtn  := startBtn;
prev_resetBtn  := resetBtn;
prev_valveOpen := valveOpen;

END_FUNCTION_BLOCK
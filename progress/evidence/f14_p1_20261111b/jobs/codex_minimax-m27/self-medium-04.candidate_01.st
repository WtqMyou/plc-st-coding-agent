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
    fillsToday : INT := 0;
END_VAR
VAR
    prevStartBtn   : BOOL := FALSE;
    prevResetBtn   : BOOL := FALSE;
    prevValveOpen  : BOOL := FALSE;
    prevDoneSensor : BOOL := FALSE;
    prevFillsToday : INT  := 0;
    
    currentVolume  : REAL := 0.0;
    pendingConfirm : BOOL := FALSE;
END_VAR

VAR_TEMP
    risingStart  : BOOL;
    risingReset  : BOOL;
    risingDone   : BOOL;
END_VAR

// 检测上升沿
risingStart  := startBtn AND NOT prevStartBtn;
risingReset  := resetBtn AND NOT prevResetBtn;
risingDone   := doneSensor AND NOT prevDoneSensor;

// ========== 1. 复位优先 ==========
IF risingReset THEN
    // 清零计数和累计体积
    fillsToday      := 0;
    currentVolume   := 0.0;
    // 关阀并清除待确认
    valveOpen       := FALSE;
    pendingConfirm  := FALSE;
ELSE
    // ========== 2. 启动新瓶 ==========
    IF risingStart THEN
        // 若上一瓶仍待确认，先取消
        pendingConfirm := FALSE;
        // 清零本瓶累计并开阀
        currentVolume  := 0.0;
        valveOpen      := TRUE;
    END_IF;
    
    // ========== 3. 灌装累计与关阀 ==========
    IF valveOpen THEN
        // 加入本拍流量，启动拍也计入
        currentVolume := currentVolume + flowVol;
        
        // 累计达到或超过目标时立即关阀并令本瓶待确认
        IF currentVolume >= targetVol THEN
            valveOpen      := FALSE;
            pendingConfirm := TRUE;
        END_IF;
    END_IF;
    
    // ========== 4. 确认逻辑 ==========
    IF pendingConfirm THEN
        // 本拍关阀后立即读取 doneSensor
        IF doneSensor THEN
            // 本拍确认并计数
            pendingConfirm := FALSE;
            
            // fillsToday 增加 1；原计数为 32767 时保持 32767
            IF fillsToday < 32767 THEN
                fillsToday := fillsToday + 1;
            END_IF;
        END_IF;
    END_IF;
END_IF;

// 更新上电前值（用于下一拍上升沿检测）
prevStartBtn   := startBtn;
prevResetBtn   := resetBtn;
prevValveOpen  := valveOpen;
prevDoneSensor := doneSensor;
prevFillsToday := fillsToday;
END_FUNCTION_BLOCK
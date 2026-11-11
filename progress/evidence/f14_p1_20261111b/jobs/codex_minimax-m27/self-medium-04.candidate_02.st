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
    
    currentVolume  : REAL := 0.0;
    pendingConfirm : BOOL := FALSE;
END_VAR

VAR_TEMP
    risingStart : BOOL;
    risingReset : BOOL;
END_VAR

risingStart := startBtn AND NOT prevStartBtn;
risingReset := resetBtn AND NOT prevResetBtn;

// ========== 1. 复位优先 ==========
IF risingReset THEN
    fillsToday      := 0;
    currentVolume   := 0.0;
    valveOpen       := FALSE;
    pendingConfirm  := FALSE;
    prevStartBtn    := resetBtn;
    prevResetBtn    := resetBtn;
    RETURN;
END_IF;

// ========== 2. 启动新瓶 ==========
IF risingStart THEN
    pendingConfirm := FALSE;
    currentVolume  := 0.0;
    
    IF flowVol >= targetVol THEN
        // 启动拍直接达标：关阀，本拍确认
        valveOpen      := FALSE;
        pendingConfirm := TRUE;
    ELSE
        valveOpen := TRUE;
    END_IF;
ELSE
    // ========== 3. 灌装累计 ==========
    IF valveOpen THEN
        currentVolume := currentVolume + flowVol;
        
        IF currentVolume >= targetVol THEN
            valveOpen      := FALSE;
            pendingConfirm := TRUE;
        END_IF;
    END_IF;
END_IF;

// ========== 4. 确认逻辑 ==========
IF pendingConfirm AND doneSensor THEN
    pendingConfirm := FALSE;
    IF fillsToday < 32767 THEN
        fillsToday := fillsToday + 1;
    END_IF;
END_IF;

prevStartBtn  := startBtn;
prevResetBtn  := resetBtn;
prevValveOpen := valveOpen;
END_FUNCTION_BLOCK
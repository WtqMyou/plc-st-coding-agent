FUNCTION_BLOCK FB
VAR_INPUT
    startBtn : BOOL;
    resetBtn : BOOL;
    doneSensor : BOOL;
    targetVol : REAL;
    flowVol : REAL;
END_VAR
VAR_OUTPUT
    valveOpen : BOOL;
    fillsToday : INT;
END_VAR
VAR
    prevStart : BOOL := FALSE;
    prevReset : BOOL := FALSE;
    pendingConfirm : BOOL := FALSE;
    accVol : REAL := 0.0;
END_VAR

// 上升沿检测
startRising := startBtn AND NOT prevStart;
resetRising := resetBtn AND NOT prevReset;

IF resetRising THEN
    // 复位优先：清零计数和累计，关阀并清除待确认
    fillsToday := 0;
    accVol := 0.0;
    valveOpen := FALSE;
    pendingConfirm := FALSE;
ELSE
    // 启动处理（空闲或等待确认时）
    IF startRising AND NOT valveOpen THEN
        accVol := 0.0;
        valveOpen := TRUE;
        pendingConfirm := FALSE; // 取消上一瓶待确认
    END_IF;

    // 灌装累加与达标关阀
    IF valveOpen THEN
        accVol := accVol + flowVol;
        IF accVol >= targetVol THEN
            valveOpen := FALSE;
            pendingConfirm := TRUE;
        END_IF;
    END_IF;

    // 确认计数（去抖与饱和处理）
    IF pendingConfirm AND doneSensor THEN
        IF fillsToday < 32767 THEN
            fillsToday := fillsToday + 1;
        END_IF;
        pendingConfirm := FALSE; // 立即清除待确认
    END_IF;
END_IF;

// 更新边沿记忆
prevStart := startBtn;
prevReset := resetBtn;

END_FUNCTION_BLOCK
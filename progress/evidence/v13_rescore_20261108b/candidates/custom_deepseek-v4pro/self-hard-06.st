FUNCTION_BLOCK FB
VAR_INPUT
    runRequest : BOOL;
    pressure : REAL;
    pressureValid : BOOL;
    fuelFlow : REAL;
    steamFlow : REAL;
    outletCmd : INT;
    outletFeedback : INT;
    resetBtn : BOOL;
END_VAR
VAR_OUTPUT
    tripLatched : BOOL;
    fuelPermit : BOOL;
    currentCauseMask : WORD;
    latchedCauseMask : WORD;
    diagnosticActive : BOOL;
END_VAR
VAR
    resetBtnPrev : BOOL := FALSE;
    resetRising : BOOL;
    valveStuckCounter : INT := 0;
    tripCondition : BOOL;
    resetCondition : BOOL;
    bit1Active : BOOL;
    bit2Active : BOOL;
    stuckCond : BOOL;
END_VAR

// 卡滞条件判断，连续满足时计数
stuckCond := runRequest AND pressureValid AND (pressure >= 4500.0) 
             AND (outletCmd >= 50) AND (outletFeedback <= 10);

IF stuckCond THEN
    valveStuckCounter := valveStuckCounter + 1;
ELSE
    valveStuckCounter := 0;
END_IF;

// 本周期诊断线索掩码计算
IF NOT runRequest THEN
    currentCauseMask := 0;
ELSIF NOT pressureValid THEN
    currentCauseMask := 16#0001; // bit0: 变送器失效
ELSE
    IF pressure >= 4500.0 THEN
        bit1Active := (valveStuckCounter >= 3);
        bit2Active := (fuelFlow >= 4.0) AND (steamFlow <= 10.0);
        IF bit1Active OR bit2Active THEN
            currentCauseMask := 0;
            IF bit1Active THEN
                currentCauseMask := currentCauseMask OR 16#0002; // bit1: 减温减压阀卡滞
            END_IF;
            IF bit2Active THEN
                currentCauseMask := currentCauseMask OR 16#0004; // bit2: 燃烧过剩
            END_IF;
        ELSE
            currentCauseMask := 16#0008; // bit3: 未定位
        END_IF;
    ELSE
        currentCauseMask := 0;
    END_IF;
END_IF;

// 复位按钮上升沿检测
resetRising := resetBtn AND NOT resetBtnPrev;

// 复位条件
resetCondition := resetRising AND (NOT runRequest) AND pressureValid 
                  AND (pressure <= 4200.0);

// 跳闸条件
tripCondition := (runRequest AND NOT pressureValid) 
                 OR (runRequest AND pressureValid AND pressure >= 4500.0);

// 更新跳闸自保持与线索足迹累积
IF resetCondition THEN
    tripLatched := FALSE;
    latchedCauseMask := 0;
ELSE
    IF tripCondition THEN
        tripLatched := TRUE;
    END_IF;
    IF tripLatched THEN
        latchedCauseMask := latchedCauseMask OR currentCauseMask;
    END_IF;
END_IF;

// 输出计算
fuelPermit := runRequest AND (NOT tripLatched);
diagnosticActive := (currentCauseMask <> 0);

// 更新历史状态
resetBtnPrev := resetBtn;

END_FUNCTION_BLOCK
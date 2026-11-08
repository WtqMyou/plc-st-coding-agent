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
    tripLatchedState : BOOL := FALSE;
    resetBtnPrev : BOOL := FALSE;
    valveStuckCounter : INT := 0;
    latchedCauseMaskInternal : WORD := 0;
    tripCondition : BOOL;
    resetBtnRising : BOOL;
    tempMask : WORD;
END_VAR

// 检测复位按钮上升沿
resetBtnRising := resetBtn AND NOT resetBtnPrev;

// 判断跳闸条件
tripCondition := (runRequest AND pressureValid AND (pressure >= 4500.0)) OR (runRequest AND NOT pressureValid);

// 跳闸条件成立则置位自保持
IF tripCondition THEN
    tripLatchedState := TRUE;
END_IF

// 复位上升沿且满足清除条件时解除跳闸
IF resetBtnRising AND NOT runRequest AND pressureValid AND (pressure <= 4200.0) THEN
    tripLatchedState := FALSE;
    latchedCauseMaskInternal := 0; // 复位时清零故障记录
END_IF

// 更新阀门卡滞计数器（跨周期记忆）
IF runRequest THEN
    IF pressureValid AND (pressure >= 4500.0) AND (outletCmd >= 50) AND (outletFeedback <= 10) THEN
        valveStuckCounter := valveStuckCounter + 1;
    ELSE
        valveStuckCounter := 0;
    END_IF
ELSE
    valveStuckCounter := 0;
END_IF

// 计算本周期线索掩码
tempMask := 0;
IF NOT runRequest THEN
    tempMask := 0;
ELSE
    IF pressureValid AND (pressure < 4500.0) THEN
        tempMask := 0;
    ELSE
        // bit0: 变送器失效
        IF NOT pressureValid THEN
            tempMask := tempMask OR 1;
        END_IF
        // bit1: 减温减压阀卡滞（连续3拍及以上）
        IF valveStuckCounter >= 3 THEN
            tempMask := tempMask OR 2;
        END_IF
        // bit2: 燃烧过剩
        IF (fuelFlow >= 4.0) AND (steamFlow <= 10.0) THEN
            tempMask := tempMask OR 4;
        END_IF
        // bit3: 未定位
        IF (tempMask = 0) AND pressureValid AND (pressure >= 4500.0) THEN
            tempMask := tempMask OR 8;
        END_IF
    END_IF
END_IF

// 跳闸时按位或累积线索
IF tripLatchedState THEN
    latchedCauseMaskInternal := latchedCauseMaskInternal OR tempMask;
END_IF

// 更新历史变量
resetBtnPrev := resetBtn;

// 输出赋值
tripLatched := tripLatchedState;
fuelPermit := runRequest AND NOT tripLatchedState;
currentCauseMask := tempMask;
latchedCauseMask := latchedCauseMaskInternal;
diagnosticActive := (tempMask <> 0);

END_FUNCTION_BLOCK
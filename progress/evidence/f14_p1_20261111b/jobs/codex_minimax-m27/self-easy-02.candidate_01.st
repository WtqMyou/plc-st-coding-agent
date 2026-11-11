FUNCTION_BLOCK FB
VAR_INPUT
    tankLevel    : REAL;      // 储罐液位百分比 0..100
    outletFlow   : REAL;      // 出口流量 m³/h (预留观测接口)
    inletPermit  : BOOL;      // 进料许可
    resetBtn     : BOOL;      // 复位按钮
END_VAR
VAR_OUTPUT
    pumpRun         : BOOL;   // 进料泵运行命令
    alarmHigh       : BOOL;   // 高液位报警
    alarmLow        : BOOL;   // 低液位报警
    outletValveOpen : BOOL;   // 出口阀开命令
END_VAR
VAR
    prevResetBtn : BOOL := FALSE;  // 上拍复位按钮状态
END_VAR

    // 检测复位按钮上升沿：FALSE -> TRUE
    VAR tempRising : BOOL;
    tempRising := resetBtn AND NOT prevResetBtn;

    // --- 高液位报警逻辑 ---
    // 危险条件成立时立即置位并锁存
    IF tankLevel >= 85.0 THEN
        alarmHigh := TRUE;
    ELSIF tempRising THEN
        // 复位沿清除：仅当危险条件已消失才清除
        alarmHigh := FALSE;
    END_IF

    // --- 低液位报警逻辑 ---
    // 危险条件成立时立即置位并锁存
    IF tankLevel <= 15.0 THEN
        alarmLow := TRUE;
    ELSIF tempRising THEN
        // 复位沿清除：仅当危险条件已消失才清除
        alarmLow := FALSE;
    END_IF

    // --- 出口阀控制 ---
    // 低报警锁存期间关闭，其他情况下开启
    outletValveOpen := NOT alarmLow;

    // --- 进料泵控制 ---
    // inletPermit 为 TRUE 且两个报警均为 FALSE 才运行
    IF inletPermit AND NOT alarmHigh AND NOT alarmLow THEN
        pumpRun := TRUE;
    ELSE
        pumpRun := FALSE;
    END_IF

    // 更新上一拍按钮状态
    prevResetBtn := resetBtn;
END_FUNCTION_BLOCK
FUNCTION_BLOCK FB
VAR_INPUT
    tankLevel : REAL;
    outletFlow : REAL;
    inletPermit : BOOL;
    resetBtn : BOOL;
END_VAR
VAR_OUTPUT
    pumpRun : BOOL;
    alarmHigh : BOOL;
    alarmLow : BOOL;
    outletValveOpen : BOOL;
END_VAR
VAR
    prevResetBtn : BOOL := FALSE;
    alarmHighState : BOOL := FALSE;
    alarmLowState : BOOL := FALSE;
    resetRising : BOOL;
END_VAR

// 上升沿检测：复位按钮从 FALSE 变为 TRUE 的当拍有效
resetRising := resetBtn AND NOT prevResetBtn;

// 报警锁存，危险条件优先，复位上升沿只能清除已脱离危险的报警
alarmHighState := (tankLevel >= 85.0) OR (alarmHighState AND NOT resetRising);
alarmLowState  := (tankLevel <= 15.0) OR (alarmLowState AND NOT resetRising);

// 更新输出报警状态
alarmHigh := alarmHighState;
alarmLow  := alarmLowState;

// 泵运行：需进料许可且无任何报警
pumpRun := inletPermit AND NOT alarmHighState AND NOT alarmLowState;

// 出口阀：低报警锁存期间关闭，其他情况开启
outletValveOpen := NOT alarmLowState;

// 保存本拍按钮状态，用于下一拍上升沿判断
prevResetBtn := resetBtn;

END_FUNCTION_BLOCK
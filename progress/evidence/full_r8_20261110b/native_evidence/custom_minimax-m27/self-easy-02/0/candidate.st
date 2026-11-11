FUNCTION_BLOCK FB
VAR_INPUT
    tankLevel    : REAL;
    outletFlow   : REAL;
    inletPermit  : BOOL;
    resetBtn     : BOOL;
END_VAR
VAR_OUTPUT
    pumpRun         : BOOL;
    alarmHigh       : BOOL;
    alarmLow        : BOOL;
    outletValveOpen : BOOL;
END_VAR
VAR
    prevResetBtn : BOOL := FALSE;
    prevAlarmHigh : BOOL := FALSE;
    prevAlarmLow  : BOOL := FALSE;
END_VAR

VAR
    resetRising : BOOL;
END_VAR

// 计算复位按钮上升沿
resetRising := resetBtn AND NOT prevResetBtn;

// 高液位报警逻辑：危险条件立即置位并锁存，复位沿清除（危险条件优先）
alarmHigh := (tankLevel >= 85.0) OR (prevAlarmHigh AND NOT resetRising);

// 低液位报警逻辑：危险条件立即置位并锁存，复位沿清除（危险条件优先）
alarmLow := (tankLevel <= 15.0) OR (prevAlarmLow AND NOT resetRising);

// 出口阀：低报警锁存期间关闭，其他情况开启
outletValveOpen := NOT alarmLow;

// 进料泵：inletPermit为TRUE且两报警均为FALSE时运行
pumpRun := inletPermit AND NOT alarmHigh AND NOT alarmLow;

// 保存本拍状态供下拍边沿检测和锁存逻辑使用
prevResetBtn := resetBtn;
prevAlarmHigh := alarmHigh;
prevAlarmLow := alarmLow;

END_FUNCTION_BLOCK
FUNCTION_BLOCK FB
VAR_INPUT
    tankLevel        : REAL;   // 储罐液位百分比 0..100
    outletFlow       : REAL;   // 出口流量 m³/h（预留观测，本题不参与逻辑）
    inletPermit      : BOOL;   // 进料许可
    resetBtn         : BOOL;   // 复位按钮，上升沿有效
END_VAR
VAR_OUTPUT
    pumpRun          : BOOL;   // 进料泵运行命令
    alarmHigh        : BOOL;   // 高液位报警，自保持
    alarmLow         : BOOL;   // 低液位报警，自保持
    outletValveOpen  : BOOL;   // 出口阀开命令
END_VAR
VAR
    prevAlarmHigh    : BOOL := FALSE;
    prevAlarmLow     : BOOL := FALSE;
    prevResetBtn     : BOOL := FALSE;
END_VAR

// 高液位报警：危险条件优先于复位沿
alarmHigh := (tankLevel >= 85.0)
             OR (prevAlarmHigh AND NOT (resetBtn AND NOT prevResetBtn));

// 低液位报警：危险条件优先于复位沿
alarmLow := (tankLevel <= 15.0)
            OR (prevAlarmLow AND NOT (resetBtn AND NOT prevResetBtn));

// 任一报警有效时禁止进料泵运行
pumpRun := inletPermit AND NOT alarmHigh AND NOT alarmLow;

// 低报警有效期间关闭出口阀，其余情况开启
outletValveOpen := NOT alarmLow;

// 保存本拍状态，供下一扫描周期使用
prevAlarmHigh := alarmHigh;
prevAlarmLow  := alarmLow;
prevResetBtn  := resetBtn;

END_FUNCTION_BLOCK
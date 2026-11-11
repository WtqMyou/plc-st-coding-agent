FUNCTION_BLOCK FB
VAR_INPUT
    flowLow : BOOL;
    ackBtn : BOOL;
    sensorOK : BOOL;
END_VAR
VAR_OUTPUT
    alarmActive : BOOL;
    alarmAcked : BOOL;
    highHigh : BOOL;
END_VAR
VAR
    prev_flowLow     : BOOL := FALSE;
    prev_ackBtn      : BOOL := FALSE;
    prev_alarmActive : BOOL := FALSE;
    prev_alarmAcked  : BOOL := FALSE;
    ackRising        : BOOL;
END_VAR

// 上升沿检测
ackRising := ackBtn AND NOT prev_ackBtn;

// 高优先级报警：传感器断线直接触发
highHigh := NOT sensorOK;

// 低优先级报警激活（alarmActive）
alarmActive := flowLow OR (prev_alarmActive AND NOT ackRising AND NOT (prev_flowLow AND prev_alarmAcked));

// 低优先级报警确认标志（alarmAcked）
alarmAcked := alarmActive AND (NOT flowLow OR ackRising OR (prev_flowLow AND prev_alarmActive AND prev_alarmAcked));

// 更新历史状态
prev_flowLow     := flowLow;
prev_ackBtn      := ackBtn;
prev_alarmActive := alarmActive;
prev_alarmAcked  := alarmAcked;

END_FUNCTION_BLOCK
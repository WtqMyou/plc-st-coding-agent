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
    prev_flowLow : BOOL := FALSE;
    prev_ackBtn : BOOL := FALSE;
END_VAR

// 高优先级报警：传感器断线时置位
highHigh := NOT sensorOK;

// 检测确认按钮上升沿
VAR rising : BOOL;
rising := ackBtn AND NOT prev_ackBtn;

// 计算新的报警状态（基于形式化性质）
VAR newAlarmActive : BOOL;
VAR newAlarmAcked : BOOL;

newAlarmActive := flowLow OR (alarmActive AND NOT rising AND NOT (prev_flowLow AND alarmAcked));

newAlarmAcked := newAlarmActive AND (NOT flowLow OR rising OR (prev_flowLow AND alarmActive AND alarmAcked));

alarmActive := newAlarmActive;
alarmAcked := newAlarmAcked;

// 更新历史变量
prev_flowLow := flowLow;
prev_ackBtn := ackBtn;

END_FUNCTION_BLOCK
FUNCTION_BLOCK FB
VAR_INPUT
    flowLow  : BOOL;
    ackBtn   : BOOL;
    sensorOK : BOOL;
END_VAR
VAR_OUTPUT
    alarmActive : BOOL;
    alarmAcked  : BOOL;
    highHigh    : BOOL;
END_VAR
VAR
    prevFlowLow : BOOL := FALSE;
    prevAckBtn  : BOOL := FALSE;
    risingEdge  : BOOL;
END_VAR

// S5: highHigh 与传感器状态双向一致
highHigh := NOT sensorOK;

// S4: 检测确认按钮上升沿
risingEdge := ackBtn AND NOT prevAckBtn;

// S1/S2/S6: 报警激活逻辑
// flowLow出现则激活；已激活且未确认时不消失；条件消失后仅确认沿清除
alarmActive := flowLow OR (alarmActive AND NOT risingEdge AND NOT (prevFlowLow AND alarmAcked));

// S4/S7: 报警已确认逻辑
// 条件消失后自动置位；确认沿出现且条件仍在时置位；保持记忆状态
alarmAcked := alarmActive AND (NOT flowLow OR risingEdge OR (prevFlowLow AND alarmAcked));

// 更新历史变量
prevFlowLow := flowLow;
prevAckBtn  := ackBtn;

END_FUNCTION_BLOCK
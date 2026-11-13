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
    ackPrev : BOOL;
    ackEdge : BOOL;
    acknowledged : BOOL;
END_VAR

ackEdge := ackBtn AND NOT ackPrev;
ackPrev := ackBtn;

(* 高优先级：传感器断线，独立判定，不被低优先级抑制 *)
highHigh := NOT sensorOK;

(* 区分实际确认记忆与输出的“条件消失、待确认清除”标志。 *)
IF flowLow THEN
    IF NOT alarmActive THEN
        acknowledged := FALSE;
    END_IF
    alarmActive := TRUE;
    IF ackEdge THEN
        acknowledged := TRUE;
    END_IF
    alarmAcked := acknowledged;
ELSIF alarmActive THEN
    IF acknowledged OR ackEdge THEN
        alarmActive := FALSE;
        alarmAcked := FALSE;
        acknowledged := FALSE;
    ELSE
        alarmAcked := TRUE;
    END_IF
ELSE
    alarmAcked := FALSE;
    acknowledged := FALSE;
END_IF
END_FUNCTION_BLOCK

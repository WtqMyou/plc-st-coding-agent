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
    ackEdgeInputPrev : BOOL;
    ackEdge : BOOL;
    alarmState : INT;
END_VAR

ackEdge := ackBtn AND NOT ackEdgeInputPrev;
ackEdgeInputPrev := ackBtn;

(* 高优先级：传感器断线，独立判定，不被低优先级抑制 *)
highHigh := NOT sensorOK;

(* 0 正常；1 激活未确认；2 激活已确认；3 条件消失但仍待人工确认。
   题面第2条把状态3的 alarmAcked 也定义为 TRUE。 *)
CASE alarmState OF
    0:
        IF flowLow THEN alarmState := 1; END_IF
    1:
        IF NOT flowLow THEN alarmState := 3; END_IF
    2:
        IF NOT flowLow THEN alarmState := 0; END_IF
    3:
        IF flowLow THEN alarmState := 1; END_IF
END_CASE
IF ackEdge THEN
    IF flowLow THEN
        alarmState := 2;
    ELSE
        alarmState := 0;
    END_IF
END_IF
alarmActive := alarmState <> 0;
alarmAcked := (alarmState = 2) OR (alarmState = 3);
END_FUNCTION_BLOCK

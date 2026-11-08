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
    ackBtnPrev : BOOL := FALSE;
END_VAR

VAR
    risingEdge : BOOL;
END_VAR

risingEdge := ackBtn AND NOT ackBtnPrev;

highHigh := NOT sensorOK;

IF flowLow THEN
    alarmActive := TRUE;
    alarmAcked := FALSE;
ELSIF alarmActive AND NOT alarmAcked THEN
    alarmAcked := TRUE;
END_IF

IF risingEdge THEN
    IF alarmActive AND NOT alarmAcked THEN
        alarmAcked := TRUE;
    ELSIF alarmActive AND alarmAcked THEN
        alarmActive := FALSE;
        alarmAcked := FALSE;
    END_IF
END_IF

ackBtnPrev := ackBtn;
END_FUNCTION_BLOCK
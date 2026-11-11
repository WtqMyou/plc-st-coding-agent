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
    risingAck : BOOL;
    flowLow_prev : BOOL := FALSE;
    prev_flowLow : BOOL;
    prev_alarmActive : BOOL := FALSE;
    prev_alarmAcked : BOOL := FALSE;
    internalActive : BOOL := FALSE;
    internalAcked : BOOL := FALSE;
END_VAR

risingAck := ackBtn AND NOT ackBtnPrev;
ackBtnPrev := ackBtn;

prev_flowLow := flowLow_prev;
flowLow_prev := flowLow;

prev_alarmActive := internalActive;
prev_alarmAcked := internalAcked;

internalActive := flowLow OR (prev_alarmActive AND NOT risingAck AND NOT (prev_flowLow AND prev_alarmAcked));
internalAcked := internalActive AND (NOT flowLow OR risingAck OR (prev_flowLow AND prev_alarmActive AND prev_alarmAcked));

alarmActive := internalActive;
alarmAcked := internalAcked;
highHigh := NOT sensorOK;

END_FUNCTION_BLOCK
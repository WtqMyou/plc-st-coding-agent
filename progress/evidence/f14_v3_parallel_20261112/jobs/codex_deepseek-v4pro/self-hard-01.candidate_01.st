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
    prevAck : BOOL;
    prevFlowLow : BOOL;
    prevAlarmActive : BOOL;
    prevAlarmAcked : BOOL;
    ackRise : BOOL;
END_VAR

ackRise := ackBtn AND NOT prevAck;

highHigh := NOT sensorOK;

alarmActive := flowLow OR (prevAlarmActive AND NOT ackRise AND NOT (prevFlowLow AND prevAlarmAcked));

alarmAcked := alarmActive AND (NOT flowLow OR ackRise OR (prevFlowLow AND prevAlarmActive AND prevAlarmAcked));

prevAck := ackBtn;
prevFlowLow := flowLow;
prevAlarmActive := alarmActive;
prevAlarmAcked := alarmAcked;

END_FUNCTION_BLOCK
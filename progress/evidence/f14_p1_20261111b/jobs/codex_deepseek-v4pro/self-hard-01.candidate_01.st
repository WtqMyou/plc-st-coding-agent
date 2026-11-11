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
    lastAck : BOOL;
    lastFlowLow : BOOL;
    lastAlarmActive : BOOL;
    lastAlarmAcked : BOOL;
    ackRise : BOOL;
    lastFlowAndAcked : BOOL;
    lastFlowActiveAcked : BOOL;
END_VAR

ackRise := ackBtn AND NOT lastAck;

lastFlowAndAcked := lastFlowLow AND lastAlarmAcked;
lastFlowActiveAcked := lastFlowLow AND lastAlarmActive AND lastAlarmAcked;

highHigh := NOT sensorOK;

alarmActive := flowLow OR (lastAlarmActive AND NOT ackRise AND NOT lastFlowAndAcked);
alarmAcked := alarmActive AND (NOT flowLow OR ackRise OR lastFlowActiveAcked);

lastAck := ackBtn;
lastFlowLow := flowLow;
lastAlarmActive := alarmActive;
lastAlarmAcked := alarmAcked;

END_FUNCTION_BLOCK
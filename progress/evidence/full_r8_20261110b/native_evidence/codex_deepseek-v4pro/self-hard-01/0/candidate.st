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
    ackOld : BOOL;
    ackRising : BOOL;
    prevFlowLow : BOOL;
    prevAlarmActive : BOOL;
    prevAlarmAcked : BOOL;
END_VAR

ackRising := ackBtn AND NOT ackOld;

highHigh := NOT sensorOK;

alarmActive := flowLow OR
               (prevAlarmActive AND NOT ackRising AND NOT (prevFlowLow AND prevAlarmAcked));

alarmAcked := alarmActive AND
              (NOT flowLow OR ackRising OR (prevFlowLow AND prevAlarmActive AND prevAlarmAcked));

ackOld := ackBtn;
prevFlowLow := flowLow;
prevAlarmActive := alarmActive;
prevAlarmAcked := alarmAcked;

END_FUNCTION_BLOCK
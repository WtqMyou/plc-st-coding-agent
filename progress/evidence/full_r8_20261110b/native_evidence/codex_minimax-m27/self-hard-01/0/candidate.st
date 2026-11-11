FUNCTION_BLOCK FB
VAR_INPUT
    flowLow   : BOOL;
    ackBtn    : BOOL;
    sensorOK  : BOOL;
END_VAR

VAR_OUTPUT
    alarmActive : BOOL;
    alarmAcked  : BOOL;
    highHigh    : BOOL;
END_VAR

VAR
    prevAckBtn  : BOOL := FALSE;
    prevFlowLow : BOOL := FALSE;
END_VAR

VAR_TEMP
    risingAck : BOOL;
END_VAR

risingAck := ackBtn AND NOT prevAckBtn;

highHigh := NOT sensorOK;

alarmActive := flowLow OR (alarmActive AND NOT risingAck AND NOT (prevFlowLow AND alarmAcked));

alarmAcked := alarmActive AND (NOT flowLow OR risingAck OR (prevFlowLow AND alarmAcked));

prevAckBtn := ackBtn;
prevFlowLow := flowLow;
END_FUNCTION_BLOCK
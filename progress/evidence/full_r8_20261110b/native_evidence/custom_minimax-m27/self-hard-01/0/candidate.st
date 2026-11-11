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
    prev_flowLow     : BOOL := FALSE;
    prev_ackBtn      : BOOL := FALSE;
    prev_alarmActive : BOOL := FALSE;
    prev_alarmAcked  : BOOL := FALSE;
    risingAck        : BOOL;
END_VAR

    risingAck := ackBtn AND NOT prev_ackBtn;

    highHigh := NOT sensorOK;

    IF flowLow THEN
        alarmActive := TRUE;
    ELSIF prev_alarmActive AND NOT prev_alarmAcked THEN
        alarmActive := TRUE;
    ELSE
        alarmActive := FALSE;
    END_IF

    IF flowLow AND risingAck THEN
        alarmAcked := TRUE;
    ELSIF NOT flowLow AND alarmActive THEN
        alarmAcked := TRUE;
    ELSE
        alarmAcked := FALSE;
    END_IF

    prev_flowLow     := flowLow;
    prev_ackBtn      := ackBtn;
    prev_alarmActive := alarmActive;
    prev_alarmAcked  := alarmAcked;
END_FUNCTION_BLOCK
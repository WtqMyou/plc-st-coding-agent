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
    prev_ackBtn : BOOL;
END_VAR

VAR_TEMP
    rising_ackBtn : BOOL;
END_VAR

rising_ackBtn := ackBtn AND NOT prev_ackBtn;

// S5: High priority alarm - sensor failure
highHigh := NOT sensorOK;

// Low priority alarm state machine
IF flowLow THEN
    // Condition present: activate alarm, reset acknowledgment
    alarmActive := TRUE;
    alarmAcked := FALSE;
    
ELSIF rising_ackBtn AND alarmActive THEN
    // Acknowledge button pressed while alarm active: mark acknowledged
    alarmAcked := TRUE;
    
ELSIF alarmActive AND alarmAcked THEN
    // Condition cleared and already acknowledged: clear alarm
    alarmActive := FALSE;
    alarmAcked := FALSE;
    
END_IF;

prev_ackBtn := ackBtn;

END_FUNCTION_BLOCK
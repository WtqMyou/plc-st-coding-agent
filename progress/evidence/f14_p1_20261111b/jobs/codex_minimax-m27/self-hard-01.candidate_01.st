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
    prev_ackBtn   : BOOL;    (* Previous cycle ackBtn state for rising edge detection *)
END_VAR

VAR_TEMP
    rising_ackBtn : BOOL;    (* Rising edge of ackBtn in current cycle *)
END_VAR

// Detect rising edge of acknowledge button
rising_ackBtn := ackBtn AND NOT prev_ackBtn;

// S5: High priority alarm - sensor failure
highHigh := NOT sensorOK;

// Low priority alarm state machine
// Priority: reset alarmAcked on new flowLow > acknowledge on rising edge > clear on condition gone + acknowledged

IF flowLow THEN
    // Condition occurred: activate alarm, reset acknowledgment
    alarmActive := TRUE;
    alarmAcked := FALSE;
    
ELSIF rising_ackBtn AND alarmActive THEN
    // Acknowledge button pressed while alarm active
    alarmAcked := TRUE;
    
ELSIF NOT flowLow AND alarmAcked THEN
    // Condition cleared and already acknowledged: clear alarm
    alarmActive := FALSE;
    alarmAcked := FALSE;
    
END_IF;

// Update previous state for next cycle
prev_ackBtn := ackBtn;

END_FUNCTION_BLOCK
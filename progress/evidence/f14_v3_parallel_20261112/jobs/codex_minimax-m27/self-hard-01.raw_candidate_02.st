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
    prev_flowLow : BOOL := FALSE;
    prev_ackBtn  : BOOL := FALSE;
END_VAR

VAR_TEMP
    risingAck : BOOL;
END_VAR

risingAck := ackBtn AND NOT prev_ackBtn;

IF flowLow THEN
    // Condition is active
    IF NOT alarmActive THEN
        // New alarm activation
        alarmActive := TRUE;
        alarmAcked  := FALSE;
    ELSIF risingAck THEN
        // Rising ack while condition still exists - just mark acknowledged
        alarmAcked := TRUE;
    END_IF;
ELSE
    // Condition has disappeared
    IF prev_flowLow AND alarmAcked THEN
        // Condition just cleared, was already acknowledged - clear immediately
        alarmActive := FALSE;
        alarmAcked  := FALSE;
    ELSIF prev_flowLow AND NOT alarmAcked THEN
        // Condition just cleared, unacknowledged - enter pending clear state
        alarmAcked := TRUE;
    ELSIF risingAck AND alarmAcked THEN
        // Condition still gone from before, pending clear - clear on new ack
        alarmActive := FALSE;
        alarmAcked  := FALSE;
    END_IF;
END_IF;

// High priority alarm: sensor failure (independent)
highHigh := NOT sensorOK;

// Update state for next cycle
prev_flowLow := flowLow;
prev_ackBtn  := ackBtn;

END_FUNCTION_BLOCK
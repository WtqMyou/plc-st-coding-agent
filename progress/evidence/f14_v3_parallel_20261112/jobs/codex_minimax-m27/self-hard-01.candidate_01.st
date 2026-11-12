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
    prev_flowLow   : BOOL := FALSE;
    prev_ackBtn    : BOOL := FALSE;
    prev_alarmAcked : BOOL := FALSE;
END_VAR

VAR_TEMP
    risingAck : BOOL;
END_VAR

// Detect rising edge of ackBtn
risingAck := ackBtn AND NOT prev_ackBtn;

// Alarm state machine
IF flowLow THEN
    // Condition is active
    IF NOT alarmActive THEN
        // New alarm activation
        alarmActive := TRUE;
        alarmAcked  := FALSE;
    ELSIF risingAck THEN
        // Acknowledge while condition still exists
        alarmAcked := TRUE;
    END_IF;
ELSE
    // Condition has disappeared
    IF alarmActive AND NOT alarmAcked THEN
        // Unacknowledged alarm - enter pending clear state
        alarmAcked := TRUE;
    ELSIF alarmActive AND alarmAcked AND risingAck THEN
        // Acknowledged alarm with condition cleared - clear alarm
        alarmActive := FALSE;
        alarmAcked  := FALSE;
    END_IF;
END_IF;

// High priority alarm: sensor failure (independent of low priority alarm)
highHigh := NOT sensorOK;

// Update state for next cycle
prev_flowLow    := flowLow;
prev_ackBtn     := ackBtn;
prev_alarmAcked := alarmAcked;

END_FUNCTION_BLOCK
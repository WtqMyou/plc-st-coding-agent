FUNCTION_BLOCK FB
VAR_INPUT
    flowLow  : BOOL;
    ackBtn   : BOOL;
    sensorOK : BOOL;
END_VAR
VAR_OUTPUT
    alarmActive : BOOL;
    alarmAcked  : BOOL;
    highHigh    : BOOL;
END_VAR
VAR
    prevAckBtn  : BOOL := FALSE;
    prevFlowLow : BOOL := FALSE;
    risingAck   : BOOL;
    risingFlow  : BOOL;
END_VAR

    // Rising edge detection
    risingAck  := ackBtn AND NOT prevAckBtn;
    risingFlow := flowLow AND NOT prevFlowLow;

    // High-priority: sensor failure
    highHigh := NOT sensorOK;

    // Main alarm logic
    IF risingFlow THEN
        // Condition reappeared → unacknowledged active alarm
        alarmActive := TRUE;
        alarmAcked  := FALSE;
    ELSIF risingAck THEN
        // Acknowledge button pressed
        IF flowLow THEN
            // Condition still present: acknowledge only
            alarmActive := TRUE;
            alarmAcked  := TRUE;
        ELSE
            // Condition already gone: clear alarm
            alarmActive := FALSE;
            alarmAcked  := FALSE;
        END_IF;
    ELSIF alarmActive AND NOT alarmAcked AND NOT flowLow THEN
        // Condition disappeared before acknowledgment → pending clear
        alarmActive := TRUE;
        alarmAcked  := TRUE;
    END_IF;

    prevAckBtn  := ackBtn;
    prevFlowLow := flowLow;
END_FUNCTION_BLOCK
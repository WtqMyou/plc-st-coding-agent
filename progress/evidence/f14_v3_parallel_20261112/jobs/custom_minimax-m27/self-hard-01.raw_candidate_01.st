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
    state        : UINT := 0;  // 0=IDLE, 1=UNACKED, 2=PENDING_CLEAR
    prevAckBtn   : BOOL := FALSE;
    prevFlowLow  : BOOL := FALSE;
    prevAlarmActive  : BOOL := FALSE;
    prevAlarmAcked   : BOOL := FALSE;
    risingEdge   : BOOL;   // rising edge of ackBtn
    risingEdge2  : BOOL;   // rising edge of flowLow
END_VAR

    // Edge detection
    risingEdge  := ackBtn AND NOT prevAckBtn;
    risingEdge2 := flowLow AND NOT prevFlowLow;

    // Update previous-cycle outputs for formal-property checks
    prevAlarmActive := alarmActive;
    prevAlarmAcked  := alarmAcked;

    // High-priority alarm: sensor failure
    highHigh := NOT sensorOK;

    // State machine
    CASE state OF
        0:  // IDLE
            alarmActive := FALSE;
            alarmAcked  := FALSE;
            IF risingEdge2 THEN
                state       := 1;
                alarmActive := TRUE;
                alarmAcked  := FALSE;
            ELSIF risingEdge AND flowLow THEN
                state       := 1;
                alarmActive := TRUE;
                alarmAcked  := FALSE;
            END_IF;

        1:  // UNACKED
            alarmActive := TRUE;
            alarmAcked  := FALSE;
            IF risingEdge2 THEN
                state := 1;  // re-triggered; remain UNACKED
            ELSIF risingEdge THEN
                state := 0;  // acked while condition still present
            ELSIF NOT flowLow THEN
                state       := 2;
                alarmAcked  := TRUE;  // condition gone, waiting for ack
            END_IF;

        2:  // PENDING_CLEAR
            alarmActive := TRUE;
            alarmAcked  := TRUE;
            IF risingEdge2 THEN
                state       := 1;
                alarmAcked  := FALSE;  // condition reappeared before ack
            ELSIF risingEdge THEN
                state       := 0;      // acked; condition already gone
                alarmActive := FALSE;
                alarmAcked  := FALSE;
            END_IF;
    END_CASE;

    // Shift register for next cycle edge detection
    prevAckBtn  := ackBtn;
    prevFlowLow := flowLow;
END_FUNCTION_BLOCK
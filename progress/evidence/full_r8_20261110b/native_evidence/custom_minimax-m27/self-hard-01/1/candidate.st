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
    state        : INT := 0;
END_VAR

    highHigh := NOT sensorOK;

    IF state = 0 THEN
        IF flowLow THEN
            alarmActive := TRUE;
            alarmAcked := FALSE;
            state := 1;
        ELSE
            alarmActive := FALSE;
            alarmAcked := FALSE;
        END_IF
    ELSIF state = 1 THEN
        IF NOT flowLow AND prev_flowLow THEN
            alarmActive := TRUE;
            alarmAcked := TRUE;
        ELSIF ackBtn AND NOT prev_ackBtn AND flowLow THEN
            alarmActive := FALSE;
            alarmAcked := FALSE;
            state := 0;
        ELSE
            alarmActive := TRUE;
            alarmAcked := (flowLow AND ackBtn AND NOT prev_ackBtn) OR alarmAcked;
        END_IF
    END_IF

    prev_flowLow := flowLow;
    prev_ackBtn := ackBtn;
END_FUNCTION_BLOCK
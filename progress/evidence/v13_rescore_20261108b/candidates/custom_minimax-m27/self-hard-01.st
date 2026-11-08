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
    prevAckBtn    : BOOL := FALSE;
    prevFlowLow   : BOOL := FALSE;
    xAlarmActive  : BOOL := FALSE;
    xAlarmAcked   : BOOL := FALSE;
END_VAR

(* New alarm on rising edge of flowLow *)
IF flowLow AND NOT prevFlowLow THEN
    xAlarmActive := TRUE;
    xAlarmAcked  := FALSE;
END_IF

(* Condition disappeared: set pending flag *)
IF NOT flowLow AND prevFlowLow THEN
    IF xAlarmActive AND NOT xAlarmAcked THEN
        xAlarmAcked := TRUE;
    END_IF;
END_IF

(* Acknowledge on rising edge of ack button *)
IF ackBtn AND NOT prevAckBtn THEN
    IF flowLow = FALSE AND xAlarmActive AND xAlarmAcked THEN
        xAlarmActive := FALSE;
        xAlarmAcked  := FALSE;
    ELSIF flowLow = TRUE AND xAlarmActive THEN
        xAlarmAcked := TRUE;
    END_IF;
END_IF

(* High‑priority alarm for sensor failure *)
highHigh := NOT sensorOK;

(* Drive outputs *)
alarmActive := xAlarmActive;
alarmAcked  := xAlarmAcked;

(* Update edge‑detection history *)
prevAckBtn  := ackBtn;
prevFlowLow := flowLow;

END_FUNCTION_BLOCK
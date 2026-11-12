FUNCTION_BLOCK FB
VAR_INPUT
    flowLow   : BOOL;
    ackBtn    : BOOL;
    sensorOK  : BOOL;
END_VAR
VAR_OUTPUT
    alarmActive  : BOOL;
    alarmAcked   : BOOL;
    highHigh     : BOOL;
END_VAR
VAR
    prev_flowLow  : BOOL := FALSE;
    prev_ackBtn   : BOOL := FALSE;
END_VAR
// ENGINEERING_CONTRACT
// State machine: Four-state alarm model per ISA-18.2
// alarmActive: LATCHED until acknowledged then cleared (PUB001, PUB005, PUB006, PUB007)
// alarmAcked:  SET on rising ackBtn while condition present OR when condition clears
//              while unacknowledged (PUB005, PUB006, PUB007); clears with alarmActive
// highHigh:    UNLATCHED, direct sensorOK inverse (PUB004, PUB008)
// State table:
//   Condition present & unacked  -> alarmActive=TRUE, alarmAcked=FALSE
//   Condition present & acked    -> alarmActive=TRUE, alarmAcked=TRUE
//   Condition cleared & unacked  -> alarmActive=TRUE, alarmAcked=TRUE (pending clear)
//   Rising ackBtn in cleared     -> alarmActive=FALSE, alarmAcked=FALSE
// Scan order: alarmActive/alarmAcked first, then rising-edge check, then sensor.
// CONTRACT_RULES [{"kind": "hold_until_reset", "output": "alarmActive", "set_input": "flowLow", "reset_input": "ackBtn"}]

alarmActive := flowLow OR (alarmActive AND NOT (NOT flowLow AND alarmAcked));
alarmAcked  := (NOT flowLow AND alarmActive AND NOT prev_flowLow) OR (prev_flowLow AND alarmActive);

IF (NOT prev_ackBtn AND ackBtn) THEN
    IF NOT flowLow THEN
        alarmActive := FALSE;
        alarmAcked  := FALSE;
    ELSE
        alarmAcked := TRUE;
    END_IF;
END_IF;

prev_flowLow := flowLow;
prev_ackBtn  := ackBtn;
highHigh     := NOT sensorOK;
END_FUNCTION_BLOCK
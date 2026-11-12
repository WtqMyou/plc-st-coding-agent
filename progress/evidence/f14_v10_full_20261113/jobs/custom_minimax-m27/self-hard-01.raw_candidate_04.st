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
    prev_flowLow     : BOOL := FALSE;
    prev_ackBtn      : BOOL := FALSE;
    prev_alarmActive : BOOL := FALSE;
END_VAR
// ENGINEERING_CONTRACT
// State machine: Four-state alarm model per ISA-18.2
// alarmActive: LATCHED until acknowledged then cleared (PUB001, PUB005, PUB006, PUB007)
// alarmAcked:  SET when condition clears while alarmActive (pending clear) OR
//              on rising ackBtn while alarmActive; TRUE when condition present and
//              previously acknowledged (PUB005, PUB006, PUB007)
// highHigh:    UNLATCHED, direct sensorOK inverse (PUB004, PUB008)
// Scan order: alarmActive first, then rising-edge check, then sensor.
// CONTRACT_RULES [{"kind": "hold_until_reset", "output": "alarmActive", "set_input": "flowLow", "reset_input": "ackBtn"}]

alarmActive := flowLow OR (alarmActive AND NOT (NOT flowLow AND alarmAcked));

IF (NOT prev_ackBtn AND ackBtn) THEN
    IF NOT flowLow THEN
        alarmActive := FALSE;
        alarmAcked  := FALSE;
    ELSE
        alarmAcked := TRUE;
    END_IF;
END_IF;

alarmAcked := alarmAcked OR (NOT flowLow AND alarmActive AND prev_flowLow AND prev_alarmActive);

prev_alarmActive := alarmActive;
prev_flowLow     := flowLow;
prev_ackBtn      := ackBtn;
highHigh         := NOT sensorOK;
END_FUNCTION_BLOCK
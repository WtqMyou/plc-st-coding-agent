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
    prev_flowLow : BOOL := FALSE;
    prev_ackBtn  : BOOL := FALSE;
END_VAR
// ENGINEERING_CONTRACT
// State machine: Four-state alarm model per ISA-18.2
// State transitions:
//   S1 (fresh alarm):    flowLow rises          -> alarmActive=TRUE, alarmAcked=FALSE
//   S2 (pending-clear):  flowLow falls (unacked) -> alarmActive=TRUE, alarmAcked=TRUE
//   S3 (cleared):        rising ackBtn in S2    -> alarmActive=FALSE, alarmAcked=FALSE
//   S4 (re-alarm):       flowLow rises in S2    -> alarmActive=TRUE, alarmAcked=FALSE
// Scan order: rising-edge flags computed first, then alarmActive/alarmAcked, then sensor.
// CONTRACT_RULES [{"kind": "hold_until_reset", "output": "alarmActive", "set_input": "flowLow", "reset_input": "ackBtn"}]

// Rising-edge detection (must precede assignments to avoid circular dependency)
VAR_TEMP
    rising_flowLow : BOOL;
    rising_ackBtn  : BOOL;
END_VAR

rising_flowLow := flowLow AND NOT prev_flowLow;
rising_ackBtn  := ackBtn  AND NOT prev_ackBtn;

// alarmActive: persists through pending-clear (prev_flowLow AND alarmAcked)
// alarmAcked:  set on falling flowLow while active; reset on rising flowLow or rising ackBtn

alarmActive := flowLow OR (alarmActive AND (flowLow OR (prev_flowLow AND alarmAcked)));
alarmAcked  := (rising_flowLow AND alarmActive) OR (NOT flowLow AND alarmActive) OR (rising_ackBtn AND alarmActive);

// Update previous-state flags
prev_flowLow := flowLow;
prev_ackBtn  := ackBtn;

// High-priority sensor-failure alarm (unlatched, direct inverse of sensorOK)
highHigh := NOT sensorOK;
END_FUNCTION_BLOCK
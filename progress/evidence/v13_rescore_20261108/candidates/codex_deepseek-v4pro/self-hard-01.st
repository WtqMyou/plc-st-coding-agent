FUNCTION_BLOCK FB
VAR_INPUT
    flowLow : BOOL;
    ackBtn : BOOL;
    sensorOK : BOOL;
END_VAR
VAR_OUTPUT
    alarmActive : BOOL;
    alarmAcked : BOOL;
    highHigh : BOOL;
END_VAR
VAR
    lastAck : BOOL := FALSE;
    lastFlow : BOOL := FALSE;
    ackRise : BOOL;
    flowRise : BOOL;
    activeState : BOOL := FALSE;
    ackState : BOOL := FALSE;
END_VAR

ackRise := ackBtn AND NOT lastAck;
flowRise := flowLow AND NOT lastFlow;

IF ackRise THEN
    IF flowLow THEN
        activeState := TRUE;
        ackState := TRUE;
    ELSE
        activeState := FALSE;
        ackState := FALSE;
    END_IF;
ELSIF flowRise THEN
    activeState := TRUE;
    ackState := FALSE;
ELSIF flowLow THEN
    activeState := TRUE;
ELSE
    IF NOT activeState THEN
        activeState := FALSE;
        ackState := FALSE;
    ELSIF NOT ackState THEN
        activeState := TRUE;
        ackState := TRUE;
    ELSE
        activeState := FALSE;
        ackState := FALSE;
    END_IF;
END_IF;

alarmActive := activeState;
alarmAcked := ackState;
highHigh := NOT sensorOK;

lastAck := ackBtn;
lastFlow := flowLow;
END_FUNCTION_BLOCK
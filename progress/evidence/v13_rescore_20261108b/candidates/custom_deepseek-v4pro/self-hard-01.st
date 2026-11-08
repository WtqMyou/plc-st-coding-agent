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
    ackBtnPrev : BOOL := FALSE;
    ackRising : BOOL;
END_VAR

ackRising := ackBtn AND NOT ackBtnPrev;
ackBtnPrev := ackBtn;

highHigh := NOT sensorOK;

IF flowLow THEN
    IF ackRising THEN
        alarmActive := TRUE;
        alarmAcked := TRUE;
    ELSE
        alarmActive := TRUE;
        IF alarmAcked THEN
            alarmAcked := TRUE;
        ELSE
            alarmAcked := FALSE;
        END_IF
    END_IF
ELSE
    IF alarmActive THEN
        IF alarmAcked THEN
            alarmActive := FALSE;
            alarmAcked := FALSE;
        ELSE
            IF ackRising THEN
                alarmActive := FALSE;
                alarmAcked := FALSE;
            ELSE
                alarmActive := TRUE;
                alarmAcked := FALSE;
            END_IF
        END_IF
    ELSE
        alarmActive := FALSE;
        alarmAcked := FALSE;
    END_IF
END_IF

END_FUNCTION_BLOCK
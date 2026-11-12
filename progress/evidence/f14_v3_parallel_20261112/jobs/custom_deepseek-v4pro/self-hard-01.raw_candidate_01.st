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
    prevA : BOOL := FALSE;
    prevK : BOOL := FALSE;
    prevF : BOOL := FALSE;
    prevAckBtn : BOOL := FALSE;
    rising_ack : BOOL;
    A : BOOL;
    K : BOOL;
END_VAR

rising_ack := ackBtn AND NOT prevAckBtn;

A := flowLow OR (prevA AND NOT rising_ack AND NOT (prevF AND prevK));

K := A AND (NOT flowLow OR rising_ack OR (prevF AND prevA AND prevK));

alarmActive := A;
alarmAcked := K;
highHigh := NOT sensorOK;

prevA := A;
prevK := K;
prevF := flowLow;
prevAckBtn := ackBtn;
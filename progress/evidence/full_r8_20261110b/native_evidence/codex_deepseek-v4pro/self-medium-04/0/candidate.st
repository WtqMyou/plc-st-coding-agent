FUNCTION_BLOCK FB
VAR_INPUT
    startBtn : BOOL;
    resetBtn : BOOL;
    doneSensor : BOOL;
    targetVol : REAL;
    flowVol : REAL;
END_VAR
VAR_OUTPUT
    valveOpen : BOOL;
    fillsToday : INT;
END_VAR
VAR
    accVol : REAL;
    pendingConfirm : BOOL;
    startPrev : BOOL;
    resetPrev : BOOL;
    startRising : BOOL;
    resetRising : BOOL;
    valveWasOpen : BOOL;
END_VAR

startRising := startBtn AND NOT startPrev;
resetRising := resetBtn AND NOT resetPrev;
valveWasOpen := valveOpen;

IF resetRising THEN
    valveOpen := FALSE;
    fillsToday := 0;
    accVol := 0.0;
    pendingConfirm := FALSE;

ELSIF startRising AND NOT valveWasOpen THEN
    accVol := flowVol;
    valveOpen := accVol < targetVol;
    pendingConfirm := NOT valveOpen;

ELSIF valveWasOpen THEN
    accVol := accVol + flowVol;
    IF accVol < targetVol THEN
        valveOpen := TRUE;
        pendingConfirm := FALSE;
    ELSE
        valveOpen := FALSE;
        pendingConfirm := TRUE;
    END_IF

ELSIF pendingConfirm THEN
    valveOpen := FALSE;
    IF doneSensor THEN
        IF fillsToday < 32767 THEN
            fillsToday := fillsToday + 1;
        END_IF
        pendingConfirm := FALSE;
        accVol := 0.0;
    END_IF

ELSE
    valveOpen := FALSE;
    pendingConfirm := FALSE;
    accVol := 0.0;
END_IF

startPrev := startBtn;
resetPrev := resetBtn;

END_FUNCTION_BLOCK
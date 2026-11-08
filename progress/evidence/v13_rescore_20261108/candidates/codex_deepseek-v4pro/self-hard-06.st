FUNCTION_BLOCK FB
VAR_INPUT
    runRequest : BOOL;
    pressure : REAL;
    pressureValid : BOOL;
    fuelFlow : REAL;
    steamFlow : REAL;
    outletCmd : INT;
    outletFeedback : INT;
    resetBtn : BOOL;
END_VAR
VAR_OUTPUT
    tripLatched : BOOL;
    fuelPermit : BOOL;
    currentCauseMask : WORD;
    latchedCauseMask : WORD;
    diagnosticActive : BOOL;
END_VAR
VAR
    resetBtnPrev : BOOL;
    resetRising : BOOL;
    valveStuckCnt : INT;
END_VAR

resetRising := resetBtn AND NOT resetBtnPrev;

IF runRequest AND pressureValid AND (pressure >= 4500.0)
   AND (outletCmd >= 50) AND (outletFeedback <= 10) THEN
    valveStuckCnt := valveStuckCnt + 1;
ELSE
    valveStuckCnt := 0;
END_IF

currentCauseMask := 0;

IF runRequest THEN
    IF NOT pressureValid THEN
        currentCauseMask := currentCauseMask OR WORD#16#0001;
    ELSIF pressure >= 4500.0 THEN
        IF valveStuckCnt >= 3 THEN
            currentCauseMask := currentCauseMask OR WORD#16#0002;
        END_IF
        IF fuelFlow >= 4.0 AND steamFlow <= 10.0 THEN
            currentCauseMask := currentCauseMask OR WORD#16#0004;
        END_IF
        IF currentCauseMask = 0 THEN
            currentCauseMask := WORD#16#0008;
        END_IF
    END_IF
END_IF

IF runRequest AND (NOT pressureValid OR pressure >= 4500.0) THEN
    tripLatched := TRUE;
ELSIF resetRising AND NOT runRequest AND pressureValid AND pressure <= 4200.0 THEN
    tripLatched := FALSE;
    latchedCauseMask := 0;
END_IF

IF tripLatched THEN
    latchedCauseMask := latchedCauseMask OR currentCauseMask;
END_IF

fuelPermit := runRequest AND NOT tripLatched;
diagnosticActive := currentCauseMask <> 0;

resetBtnPrev := resetBtn;

END_FUNCTION_BLOCK
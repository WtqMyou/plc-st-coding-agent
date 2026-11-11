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
    resetPrev : BOOL := FALSE;
    resetRising : BOOL;
    resetAllowed : BOOL;
    tripPending : BOOL;
    overpressureActive : BOOL;
    valveStuckActive : BOOL;
    stuckCounter : INT := 0;
END_VAR

resetRising := resetBtn AND NOT resetPrev;

overpressureActive := runRequest AND pressureValid AND (pressure >= 4500.0);

IF overpressureActive AND (outletCmd >= 50) AND (outletFeedback <= 10) THEN
    IF stuckCounter < 3 THEN
        stuckCounter := stuckCounter + 1;
    END_IF;
ELSE
    stuckCounter := 0;
END_IF;

valveStuckActive := stuckCounter >= 3;

currentCauseMask := WORD#0;

IF runRequest AND NOT pressureValid THEN
    currentCauseMask := WORD#1;
ELSIF overpressureActive THEN
    IF valveStuckActive THEN
        currentCauseMask := currentCauseMask OR WORD#2;
    END_IF;

    IF (fuelFlow >= 4.0) AND (steamFlow <= 10.0) THEN
        currentCauseMask := currentCauseMask OR WORD#4;
    END_IF;

    IF currentCauseMask = WORD#0 THEN
        currentCauseMask := WORD#8;
    END_IF;
END_IF;

resetAllowed := resetRising AND NOT runRequest AND pressureValid AND (pressure <= 4200.0);
tripPending := runRequest AND ((NOT pressureValid) OR (pressure >= 4500.0));

IF resetAllowed THEN
    tripLatched := FALSE;
ELSE
    tripLatched := tripLatched OR tripPending;
END_IF;

fuelPermit := runRequest AND NOT tripLatched;
diagnosticActive := currentCauseMask <> WORD#0;

IF tripLatched THEN
    latchedCauseMask := latchedCauseMask OR currentCauseMask;
ELSE
    latchedCauseMask := WORD#0;
END_IF;

resetPrev := resetBtn;
END_FUNCTION_BLOCK
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
    prevResetBtn : BOOL := FALSE;
    stuckCount : INT := 0;
    oldTrip : BOOL;
    oldLatched : WORD;
    resetRising : BOOL;
    legalReset : BOOL;
    tripCondition : BOOL;
    bit1 : BOOL;
    bit2 : BOOL;
END_VAR

oldTrip := tripLatched;
oldLatched := latchedCauseMask;
resetRising := resetBtn AND NOT prevResetBtn;
legalReset := resetRising AND NOT runRequest AND pressureValid AND (pressure <= 4200.0);
tripCondition := runRequest AND (NOT pressureValid OR (pressure >= 4500.0));
tripLatched := tripCondition OR (oldTrip AND NOT legalReset);

currentCauseMask := 0;

IF NOT runRequest THEN
    currentCauseMask := 0;
    stuckCount := 0;
ELSIF runRequest AND NOT pressureValid THEN
    currentCauseMask := 1;
    stuckCount := 0;
ELSIF runRequest AND pressureValid AND pressure < 4500.0 THEN
    currentCauseMask := 0;
    stuckCount := 0;
ELSE
    // runRequest AND pressureValid AND pressure >= 4500.0
    IF (outletCmd >= 50) AND (outletFeedback <= 10) THEN
        IF stuckCount < 3 THEN
            stuckCount := stuckCount + 1;
        END_IF;
    ELSE
        stuckCount := 0;
    END_IF;
    bit1 := stuckCount >= 3;
    bit2 := (fuelFlow >= 4.0) AND (steamFlow <= 10.0);
    IF bit1 AND bit2 THEN
        currentCauseMask := 6;
    ELSIF bit1 THEN
        currentCauseMask := 2;
    ELSIF bit2 THEN
        currentCauseMask := 4;
    ELSE
        currentCauseMask := 8;
    END_IF;
END_IF;

IF tripLatched THEN
    latchedCauseMask := (oldLatched OR currentCauseMask) AND WORD#16#000F;
ELSE
    latchedCauseMask := 0;
END_IF;

fuelPermit := runRequest AND NOT tripLatched;
diagnosticActive := (currentCauseMask <> 0);

prevResetBtn := resetBtn;
END_FUNCTION_BLOCK
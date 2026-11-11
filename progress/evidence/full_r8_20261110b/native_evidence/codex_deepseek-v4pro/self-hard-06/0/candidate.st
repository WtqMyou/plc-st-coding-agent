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
    risingReset : BOOL;
    legalReset : BOOL;
    tripCondition : BOOL;
    overpressureCondition : BOOL;
    stuckQualified : BOOL;
    excessCondition : BOOL;
    stuckCount : INT := 0;
END_VAR

risingReset := resetBtn AND NOT resetBtnPrev;
legalReset := risingReset AND NOT runRequest AND pressureValid AND (pressure <= 4200.0);

tripCondition := runRequest AND (NOT pressureValid OR (pressureValid AND pressure >= 4500.0));
overpressureCondition := runRequest AND pressureValid AND (pressure >= 4500.0);

stuckQualified := overpressureCondition AND (outletCmd >= 50) AND (outletFeedback <= 10);
IF stuckQualified THEN
    IF stuckCount < 3 THEN
        stuckCount := stuckCount + 1;
    END_IF;
ELSE
    stuckCount := 0;
END_IF;

IF NOT runRequest THEN
    currentCauseMask := WORD#0;
ELSIF NOT pressureValid THEN
    currentCauseMask := WORD#1;
ELSIF pressure >= 4500.0 THEN
    currentCauseMask := WORD#0;
    excessCondition := (fuelFlow >= 4.0) AND (steamFlow <= 10.0);

    IF stuckCount >= 3 THEN
        currentCauseMask := currentCauseMask OR WORD#2;
    END_IF;

    IF excessCondition THEN
        currentCauseMask := currentCauseMask OR WORD#4;
    END_IF;

    IF currentCauseMask = WORD#0 THEN
        currentCauseMask := WORD#8;
    END_IF;
ELSE
    currentCauseMask := WORD#0;
END_IF;

IF legalReset THEN
    tripLatched := FALSE;
ELSIF tripCondition THEN
    tripLatched := TRUE;
END_IF;

IF tripLatched THEN
    latchedCauseMask := latchedCauseMask OR currentCauseMask;
ELSE
    latchedCauseMask := WORD#0;
END_IF;

fuelPermit := runRequest AND NOT tripLatched;
diagnosticActive := currentCauseMask <> WORD#0;

resetBtnPrev := resetBtn;
END_FUNCTION_BLOCK
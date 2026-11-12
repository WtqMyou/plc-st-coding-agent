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
    prevReset : BOOL;
    prevTrip : BOOL;
    valveCnt : INT;
    tripNow : BOOL;
    validOverpressure : BOOL;
    valveJamCondition : BOOL;
    burnCondition : BOOL;
    valveJamBit : BOOL;
    burnBit : BOOL;
    resetEdge : BOOL;
    legalReset : BOOL;
    nextTrip : BOOL;
    currentMask : WORD;
    latchedStore : WORD;
END_VAR

resetEdge := resetBtn AND NOT prevReset;
legalReset := resetEdge AND NOT runRequest AND pressureValid AND (pressure <= 4200.0);
validOverpressure := runRequest AND pressureValid AND (pressure >= 4500.0);
valveJamCondition := validOverpressure AND (outletCmd >= 50) AND (outletFeedback <= 10);
burnCondition := validOverpressure AND (fuelFlow >= 4.0) AND (steamFlow <= 10.0);

IF valveJamCondition THEN
    IF valveCnt < 3 THEN
        valveCnt := valveCnt + 1;
    END_IF;
ELSE
    valveCnt := 0;
END_IF;

valveJamBit := valveCnt >= 3;
burnBit := burnCondition;

IF runRequest AND NOT pressureValid THEN
    currentMask := WORD#16#0001;
ELSIF validOverpressure THEN
    IF valveJamBit AND burnBit THEN
        currentMask := WORD#16#0006;
    ELSIF valveJamBit THEN
        currentMask := WORD#16#0002;
    ELSIF burnBit THEN
        currentMask := WORD#16#0004;
    ELSE
        currentMask := WORD#16#0008;
    END_IF;
ELSE
    currentMask := WORD#16#0000;
END_IF;

tripNow := runRequest AND (NOT pressureValid OR (pressure >= 4500.0));
IF tripNow THEN
    nextTrip := TRUE;
ELSIF legalReset THEN
    nextTrip := FALSE;
ELSE
    nextTrip := prevTrip;
END_IF;

IF nextTrip THEN
    latchedStore := latchedStore OR currentMask;
ELSE
    latchedStore := WORD#16#0000;
END_IF;

tripLatched := nextTrip;
fuelPermit := runRequest AND NOT nextTrip;
currentCauseMask := currentMask;
latchedCauseMask := latchedStore;
diagnosticActive := currentMask <> WORD#16#0000;

prevReset := resetBtn;
prevTrip := nextTrip;
END_FUNCTION_BLOCK
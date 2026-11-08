FUNCTION_BLOCK FB
VAR_INPUT
    runRequest       : BOOL;
    pressure         : REAL;
    pressureValid    : BOOL;
    fuelFlow         : REAL;
    steamFlow        : REAL;
    outletCmd        : INT;
    outletFeedback   : INT;
    resetBtn         : BOOL;
END_VAR

VAR_OUTPUT
    tripLatched      : BOOL;
    fuelPermit       : BOOL;
    currentCauseMask : WORD;
    latchedCauseMask : WORD;
    diagnosticActive : BOOL;
END_VAR

VAR
    prevResetBtn     : BOOL;
    prevTripLatched  : BOOL;
    tripLatchedOnset : BOOL;
    resetRising      : BOOL;
    tripCondition    : BOOL;
    prvStuckCounter  : INT;
END_VAR

    resetRising      := resetBtn AND NOT prevResetBtn;
    tripLatchedOnset := tripLatched AND NOT prevTripLatched;

    IF NOT runRequest THEN
        currentCauseMask := 0;
        prvStuckCounter  := 0;
    ELSE
        currentCauseMask := 0;

        IF NOT pressureValid THEN
            currentCauseMask := currentCauseMask OR 1;
        END_IF;

        IF pressureValid AND (pressure >= 4500.0)
           AND (outletCmd >= 50) AND (outletFeedback <= 10) THEN
            prvStuckCounter := prvStuckCounter + 1;
            IF prvStuckCounter >= 3 THEN
                currentCauseMask := currentCauseMask OR 2;
            END_IF;
        ELSE
            prvStuckCounter := 0;
        END_IF;

        IF (fuelFlow >= 4.0) AND (steamFlow <= 10.0) AND (pressure >= 4500.0) THEN
            currentCauseMask := currentCauseMask OR 4;
        END_IF;

        IF pressureValid AND (pressure >= 4500.0) AND (currentCauseMask = 0) THEN
            currentCauseMask := currentCauseMask OR 8;
        END_IF;
    END_IF;

    tripCondition := (runRequest AND pressureValid AND (pressure >= 4500.0))
                     OR (runRequest AND NOT pressureValid);

    IF tripCondition THEN
        tripLatched := TRUE;
    ELSIF resetRising AND NOT runRequest AND pressureValid AND (pressure <= 4200.0) THEN
        tripLatched := FALSE;
    END_IF;

    IF tripLatched THEN
        IF tripLatchedOnset THEN
            latchedCauseMask := currentCauseMask;
        ELSE
            latchedCauseMask := latchedCauseMask OR currentCauseMask;
        END_IF;
    END_IF;

    IF resetRising THEN
        latchedCauseMask := 0;
    END_IF;

    fuelPermit       := runRequest AND NOT tripLatched;
    diagnosticActive := (currentCauseMask <> 0);

    prevResetBtn    := resetBtn;
    prevTripLatched := tripLatched;
END_FUNCTION_BLOCK
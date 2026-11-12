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
    prevResetBtn     : BOOL := FALSE;
    stickyCounter    : INT  := 0;
END_VAR

// Rising edge detection for reset
VAR_TEMP
    resetRising : BOOL;
END_VAR
resetRising := resetBtn AND NOT prevResetBtn;

// S17 logic: latch holds from first trip until valid reset edge
IF resetRising AND NOT runRequest AND pressureValid AND pressure <= 4200.0 THEN
    tripLatched := FALSE;
    latchedCauseMask := 0;
ELSIF resetRising THEN
    tripLatched := TRUE;
    IF tripLatched THEN
        latchedCauseMask := latchedCauseMask OR currentCauseMask;
    END_IF;
ELSIF prevResetBtn OR tripLatched THEN
    tripLatched := TRUE;
    IF prevResetBtn OR tripLatched THEN
        latchedCauseMask := latchedCauseMask OR currentCauseMask;
    END_IF;
ELSIF runRequest AND (NOT pressureValid OR pressure >= 4500.0) THEN
    tripLatched := TRUE;
    latchedCauseMask := currentCauseMask;
ELSE
    tripLatched := FALSE;
END_IF;

// Valve sticking counter
IF NOT runRequest OR NOT pressureValid OR pressure < 4500.0 OR outletCmd < 50 OR outletFeedback > 10 THEN
    stickyCounter := 0;
ELSIF outletCmd >= 50 AND outletFeedback <= 10 THEN
    stickyCounter := stickyCounter + 1;
END_IF;

// Current cause mask
currentCauseMask := 0;
IF runRequest THEN
    IF NOT pressureValid THEN
        currentCauseMask := 1;
    ELSIF stickyCounter >= 3 THEN
        currentCauseMask := 2;
    END_IF;

    IF pressureValid AND pressure >= 4500.0 THEN
        IF fuelFlow >= 4.0 AND steamFlow <= 10.0 THEN
            currentCauseMask := currentCauseMask OR 4;
        END_IF;

        IF currentCauseMask = 0 THEN
            currentCauseMask := 8;
        END_IF;
    END_IF;
END_IF;

// Outputs
fuelPermit       := runRequest AND NOT tripLatched;
diagnosticActive := (currentCauseMask <> 0);

prevResetBtn := resetBtn;
END_FUNCTION_BLOCK
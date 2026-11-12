FUNCTION_BLOCK FB
VAR_INPUT
    runRequest      : BOOL;
    pressure        : REAL;
    pressureValid   : BOOL;
    fuelFlow        : REAL;
    steamFlow       : REAL;
    outletCmd       : INT;
    outletFeedback  : INT;
    resetBtn        : BOOL;
END_VAR
VAR_OUTPUT
    tripLatched     : BOOL;
    fuelPermit      : BOOL;
    currentCauseMask: WORD;
    latchedCauseMask: WORD;
    diagnosticActive: BOOL;
END_VAR
VAR
    prevResetBtn    : BOOL := FALSE;
    stickyCounter   : INT  := 0;
END_VAR

// Reset edge detection
IF resetBtn AND NOT prevResetBtn THEN
    // Rising edge of reset button
    IF NOT runRequest AND pressureValid AND pressure <= 4200.0 THEN
        tripLatched     := FALSE;
        latchedCauseMask := 0;
    ELSE
        tripLatched := TRUE;
    END_IF;
ELSE
    // No reset edge
    IF tripLatched THEN
        tripLatched := TRUE;
    ELSIF runRequest AND (NOT pressureValid OR pressure >= 4500.0) THEN
        tripLatched := TRUE;
    END_IF;
END_IF;

// Valve sticking counter: reset on any interruption, increment only in valid overpressure
IF NOT runRequest OR NOT pressureValid OR pressure < 4500.0 OR outletCmd < 50 OR outletFeedback > 10 THEN
    stickyCounter := 0;
ELSIF outletCmd >= 50 AND outletFeedback <= 10 THEN
    stickyCounter := stickyCounter + 1;
END_IF;

// Determine current cause mask
currentCauseMask := 0;
IF runRequest THEN
    IF NOT pressureValid THEN
        currentCauseMask := 1;  // bit0 = 1
    ELSIF stickyCounter >= 3 THEN
        currentCauseMask := 2;  // bit1 = 2
    END_IF;
    
    IF pressureValid AND pressure >= 4500.0 THEN
        IF fuelFlow >= 4.0 AND steamFlow <= 10.0 THEN
            currentCauseMask := currentCauseMask OR 4;  // bit2 = 4
        END_IF;
        
        IF currentCauseMask = 0 THEN
            currentCauseMask := 8;  // bit3 = 8
        END_IF;
    END_IF;
END_IF;

// Accumulate latched mask during trip
IF tripLatched THEN
    latchedCauseMask := latchedCauseMask OR currentCauseMask;
END_IF;

// Outputs
fuelPermit      := runRequest AND NOT tripLatched;
diagnosticActive := (currentCauseMask <> 0);

// Update previous states
prevResetBtn := resetBtn;
END_FUNCTION_BLOCK
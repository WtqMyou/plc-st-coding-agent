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
    currentCauseMask    : WORD;
    latchedCauseMask    : WORD;
    diagnosticActive   : BOOL;
END_VAR
VAR
    prev_resetBtn       : BOOL := FALSE;
    prev_runRequest     : BOOL := FALSE;
    prev_pressureValid  : BOOL := FALSE;
    prev_pressure       : REAL := 0.0;
    prev_outletCmd      : INT := 0;
    prev_outletFeedback : INT := 0;
    prev_fuelFlow       : REAL := 0.0;
    prev_steamFlow      : REAL := 0.0;
    prev_tripLatched    : BOOL := FALSE;
    prev_tripCondition  : BOOL := FALSE;
    consecutiveStickingCount : INT := 0;
    prev_stickingCondition   : BOOL := FALSE;
    prev_prev_stickingCondition : BOOL := FALSE;
END_VAR

    // Rising edge detection for reset button
    IF resetBtn AND NOT prev_resetBtn THEN
        // Valid reset: rising edge of resetBtn while stopped, data valid, pressure <= 4200
        IF prev_tripLatched AND NOT runRequest AND pressureValid AND pressure <= 4200.0 THEN
            tripLatched := FALSE;
            latchedCauseMask := 0;
        ELSE
            tripLatched := prev_tripLatched;
        END_IF
    ELSIF prev_tripLatched THEN
        tripLatched := TRUE;
    ELSIF runRequest AND (NOT pressureValid OR pressure >= 4500.0) THEN
        tripLatched := TRUE;
    ELSE
        tripLatched := FALSE;
    END_IF;

    // Current cause mask (low 4 bits of WORD)
    currentCauseMask := 0;

    IF NOT runRequest THEN
        currentCauseMask := 0;
    ELSIF NOT pressureValid THEN
        currentCauseMask := 1;  // bit0
    ELSIF pressure >= 4500.0 THEN
        // Overpressure condition - evaluate bit1 (valve sticking)
        IF (outletCmd >= 50 AND outletFeedback <= 10) THEN
            consecutiveStickingCount := consecutiveStickingCount + 1;
        ELSE
            consecutiveStickingCount := 0;
        END_IF;

        IF consecutiveStickingCount >= 3 THEN
            currentCauseMask := currentCauseMask OR 2;  // bit1
        END_IF;

        // bit2 (combustion excess)
        IF (fuelFlow >= 4.0 AND steamFlow <= 10.0) THEN
            currentCauseMask := currentCauseMask OR 4;  // bit2
        END_IF;

        // bit3 (unlocated) - only when overpressure but no bit1 or bit2
        IF (currentCauseMask AND 6) = 0 THEN
            currentCauseMask := currentCauseMask OR 8;  // bit3
        END_IF;
    END_IF;

    // Latched cause mask accumulation (footprint preservation)
    IF tripLatched THEN
        latchedCauseMask := latchedCauseMask OR currentCauseMask;
    ELSE
        latchedCauseMask := 0;
    END_IF;

    // Outputs
    fuelPermit := runRequest AND NOT tripLatched;
    diagnosticActive := (currentCauseMask <> 0);

    // Update previous states for next scan
    prev_resetBtn := resetBtn;
    prev_runRequest := runRequest;
    prev_pressureValid := pressureValid;
    prev_pressure := pressure;
    prev_outletCmd := outletCmd;
    prev_outletFeedback := outletFeedback;
    prev_fuelFlow := fuelFlow;
    prev_steamFlow := steamFlow;
    prev_tripLatched := tripLatched;
    prev_tripCondition := runRequest AND (NOT pressureValid OR pressure >= 4500.0);
    prev_stickingCondition := (outletCmd >= 50 AND outletFeedback <= 10);
    prev_prev_stickingCondition := prev_stickingCondition;

END_FUNCTION_BLOCK
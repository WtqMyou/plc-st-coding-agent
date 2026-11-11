FUNCTION_BLOCK FB
VAR_INPUT
    mode            : INT;
    resetBtn        : BOOL;
    scanSeconds     : REAL;
    tempSP          : REAL;
    tempPV          : REAL;
    flowPV          : REAL;
    manualFlowSP    : REAL;
    manualValve     : REAL;
END_VAR
VAR_OUTPUT
    flowSP          : REAL;
    valveCommand    : REAL;
    fault           : BOOL;
    normalMode      : BOOL;
END_VAR
VAR
    prevResetBtn    : BOOL := FALSE;
    prevMode        : INT;
    firstScan       : BOOL := TRUE;
    accT            : REAL := 0.0;
    accF            : REAL := 0.0;
    prevValveCommand: REAL := 0.0;
END_VAR

VAR
    eT              : REAL;
    eF              : REAL;
    trial           : REAL;
END_VAR

// Initialize outputs on first scan
IF firstScan THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    firstScan := FALSE;
END_IF

// Fault detection
fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

// Detect rising edge of resetBtn
IF resetBtn AND NOT prevResetBtn THEN
    // Reset action - back to initial state
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    accT := 0.0;
    accF := 0.0;
    normalMode := FALSE;
ELSIF fault THEN
    // Fault fallback - immediate follow manual, no integration, preset integrators
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    accT := 0.0;
    accF := 0.0;
    normalMode := FALSE;
ELSE
    // Mode switch detection (not first scan, no fault, no reset rising edge)
    IF firstScan = FALSE AND mode <> prevMode THEN
        // Bumpless transfer on mode change
        IF mode = 2 THEN
            // Switch to cascade: both outputs keep previous values
            flowSP := flowSP;
            valveCommand := valveCommand;
        ELSE
            // Switch to auto/manual: flowSP follows manual, valve keeps previous
            flowSP := manualFlowSP;
            valveCommand := valveCommand;
        END_IF
        prevMode := mode;
        normalMode := FALSE;
    ELSE
        // Check normal mode condition
        // normalMode = TRUE when: not first scan, mode unchanged, no fault, no reset rising edge
        normalMode := (firstScan = FALSE) AND (mode = prevMode) AND NOT fault AND NOT (resetBtn AND NOT prevResetBtn);
        
        IF normalMode THEN
            // Normal PI calculation
            // Outer loop: Temperature -> FlowSP
            eT := tempSP - tempPV;
            trial := accT + 0.2 * eT * scanSeconds;
            flowSP := LIMIT(0.0, 1.0 * eT + trial, 50.0);
            accT := flowSP - 1.0 * eT;
            
            // Inner loop: Flow -> Valve
            eF := flowSP - flowPV;
            trial := accF + 0.5 * eF * scanSeconds;
            valveCommand := LIMIT(0.0, 2.0 * eF + trial, 100.0);
            accF := valveCommand - 2.0 * eF;
        END_IF
    END_IF
END_IF

// Update previous cycle variables
prevMode := mode;
prevResetBtn := resetBtn;
prevValveCommand := valveCommand;
END_FUNCTION_BLOCK
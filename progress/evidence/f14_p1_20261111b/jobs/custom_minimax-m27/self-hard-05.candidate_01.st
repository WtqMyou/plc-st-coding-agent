FUNCTION_BLOCK FB
VAR_INPUT
    runRequest   : BOOL;
    flameOK      : BOOL;
    o2Valid      : BOOL;
    o2PV         : REAL;
    baseAir      : REAL;
    resetBtn     : BOOL;
END_VAR

VAR_OUTPUT
    fuelPermit   : BOOL;
    trimEnable   : BOOL;
    airTrim      : REAL;
    airCommand   : REAL;
    tripLatched  : BOOL;
    o2Fault      : BOOL;
END_VAR

VAR
    LatchTrip    : BOOL;      // internal latch for trip state
    prevResetBtn : BOOL;      // previous state of reset button for edge detection
END_VAR

// ---- Oxygen analyser fault detection ----
o2Fault := NOT o2Valid OR o2PV < 0.0 OR o2PV > 21.0;

// ---- Flame‑loss latch ----
// Set the latch the moment a flame loss occurs while the burner is requested to run
IF runRequest AND NOT flameOK THEN
    LatchTrip := TRUE;
END_IF

// Reset the latch only on the rising edge of the reset button when the burner is safely stopped
IF resetBtn AND NOT prevResetBtn AND NOT runRequest AND NOT flameOK THEN
    LatchTrip := FALSE;
END_IF

tripLatched := LatchTrip;

// ---- Fuel permit ----
fuelPermit := runRequest AND flameOK AND NOT LatchTrip;

// ---- Oxygen trim enable ----
trimEnable := fuelPermit AND NOT o2Fault;

// ---- Air trim bias ----
IF trimEnable THEN
    airTrim := 2.0 * (2.0 - o2PV);            // raw bias
    // clamp to ±10 %
    IF airTrim > 10.0 THEN
        airTrim := 10.0;
    END_IF;
    IF airTrim < -10.0 THEN
        airTrim := -10.0;
    END_IF;
ELSE
    airTrim := 0.0;
END_IF;

// ---- Air damper command ----
IF fuelPermit THEN
    airCommand := baseAir + airTrim;         // raw command
    // clamp final command to 0 % … 100 %
    IF airCommand > 100.0 THEN
        airCommand := 100.0;
    END_IF;
    IF airCommand < 0.0 THEN
        airCommand := 0.0;
    END_IF;
ELSE
    airCommand := 0.0;
END_IF;

// ---- Update edge‑detection variable ----
prevResetBtn := resetBtn;

END_FUNCTION_BLOCK
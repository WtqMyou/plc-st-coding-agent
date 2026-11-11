FUNCTION_BLOCK FB
VAR_INPUT
    runRequest : BOOL;
    flameOK : BOOL;
    o2Valid : BOOL;
    o2PV : REAL;
    baseAir : REAL;
    resetBtn : BOOL;
END_VAR
VAR_OUTPUT
    fuelPermit : BOOL;
    trimEnable : BOOL;
    airTrim : REAL;
    airCommand : REAL;
    tripLatched : BOOL;
    o2Fault : BOOL;
END_VAR
VAR
    prevResetBtn : BOOL;
    resetRising : BOOL;
    rawTrim : REAL;
    clampedTrim : REAL;
    rawCommand : REAL;
    clampedCommand : REAL;
END_VAR

// Reset button rising edge
resetRising := resetBtn AND NOT prevResetBtn;

// Trip latch logic
IF (runRequest AND NOT flameOK) THEN
    tripLatched := TRUE;
ELSIF (resetRising AND NOT runRequest AND NOT flameOK) THEN
    tripLatched := FALSE;
END_IF;

// Fuel permit
fuelPermit := runRequest AND flameOK AND NOT tripLatched;

// O2 fault
o2Fault := (NOT o2Valid) OR (o2PV < 0.0) OR (o2PV > 21.0);

// Trim enable
trimEnable := fuelPermit AND NOT o2Fault;

// Air trim calculation
rawTrim := 2.0 * (2.0 - o2PV);
IF rawTrim > 10.0 THEN
    clampedTrim := 10.0;
ELSIF rawTrim < -10.0 THEN
    clampedTrim := -10.0;
ELSE
    clampedTrim := rawTrim;
END_IF;

IF trimEnable THEN
    airTrim := clampedTrim;
ELSE
    airTrim := 0.0;
END_IF;

// Air command calculation
rawCommand := baseAir + airTrim;
IF rawCommand > 100.0 THEN
    clampedCommand := 100.0;
ELSIF rawCommand < 0.0 THEN
    clampedCommand := 0.0;
ELSE
    clampedCommand := rawCommand;
END_IF;

IF fuelPermit THEN
    airCommand := clampedCommand;
ELSE
    airCommand := 0.0;
END_IF;

// Update previous reset button state
prevResetBtn := resetBtn;

END_FUNCTION_BLOCK
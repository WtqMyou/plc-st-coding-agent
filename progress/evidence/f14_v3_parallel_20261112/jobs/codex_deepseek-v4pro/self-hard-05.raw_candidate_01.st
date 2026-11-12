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
    prevReset : BOOL;
    prevTrip : BOOL;
    resetRise : BOOL;
    rawTrim : REAL;
    rawCmd : REAL;
END_VAR

resetRise := resetBtn AND NOT prevReset;

tripLatched := (runRequest AND NOT flameOK)
    OR (prevTrip AND NOT (resetRise AND NOT runRequest AND NOT flameOK));

fuelPermit := runRequest AND flameOK AND NOT tripLatched;

o2Fault := NOT o2Valid OR o2PV < 0.0 OR o2PV > 21.0;

trimEnable := fuelPermit AND NOT o2Fault;

IF trimEnable THEN
    rawTrim := 2.0 * (2.0 - o2PV);
    IF rawTrim < -10.0 THEN
        airTrim := -10.0;
    ELSIF rawTrim > 10.0 THEN
        airTrim := 10.0;
    ELSE
        airTrim := rawTrim;
    END_IF;
ELSE
    airTrim := 0.0;
END_IF;

IF NOT fuelPermit THEN
    airCommand := 0.0;
ELSE
    rawCmd := baseAir + airTrim;
    IF rawCmd < 0.0 THEN
        airCommand := 0.0;
    ELSIF rawCmd > 100.0 THEN
        airCommand := 100.0;
    ELSE
        airCommand := rawCmd;
    END_IF;
END_IF;

prevReset := resetBtn;
prevTrip := tripLatched;

END_FUNCTION_BLOCK
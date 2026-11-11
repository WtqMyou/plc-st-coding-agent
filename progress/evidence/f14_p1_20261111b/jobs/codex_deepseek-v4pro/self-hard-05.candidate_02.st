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
    tripMemory : BOOL;
    resetPrev : BOOL;
    resetRising : BOOL;
END_VAR

resetRising := resetBtn AND NOT resetPrev;

tripMemory := (runRequest AND NOT flameOK)
              OR (tripMemory AND NOT (resetRising AND NOT runRequest AND NOT flameOK));
tripLatched := tripMemory;

fuelPermit := runRequest AND flameOK AND NOT tripLatched;

o2Fault := NOT o2Valid OR o2PV < 0.0 OR o2PV > 21.0;

trimEnable := fuelPermit AND NOT o2Fault;

IF trimEnable THEN
    airTrim := 2.0 * (2.0 - o2PV);

    IF airTrim > 10.0 THEN
        airTrim := 10.0;
    END_IF;

    IF airTrim < -10.0 THEN
        airTrim := -10.0;
    END_IF;
ELSE
    airTrim := 0.0;
END_IF;

IF fuelPermit THEN
    airCommand := baseAir + airTrim;

    IF airCommand > 100.0 THEN
        airCommand := 100.0;
    END_IF;

    IF airCommand < 0.0 THEN
        airCommand := 0.0;
    END_IF;
ELSE
    airCommand := 0.0;
END_IF;

resetPrev := resetBtn;

END_FUNCTION_BLOCK
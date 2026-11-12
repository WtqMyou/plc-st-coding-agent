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
    tripMem : BOOL;
    risingReset : BOOL;
    rawTrim : REAL;
    cmdRaw : REAL;
END_VAR

risingReset := resetBtn AND NOT prevReset;

IF (runRequest AND NOT flameOK) OR (tripMem AND NOT (risingReset AND NOT runRequest AND NOT flameOK)) THEN
    tripLatched := TRUE;
    tripMem := TRUE;
ELSE
    tripLatched := FALSE;
    tripMem := FALSE;
END_IF;

fuelPermit := runRequest AND flameOK AND NOT tripLatched;

o2Fault := (NOT o2Valid) OR (o2PV < 0.0) OR (o2PV > 21.0);

trimEnable := fuelPermit AND NOT o2Fault;

IF NOT trimEnable THEN
    airTrim := 0.0;
ELSE
    rawTrim := 2.0 * (2.0 - o2PV);
    IF rawTrim < -10.0 THEN
        airTrim := -10.0;
    ELSIF rawTrim > 10.0 THEN
        airTrim := 10.0;
    ELSE
        airTrim := rawTrim;
    END_IF;
END_IF;

IF NOT fuelPermit THEN
    airCommand := 0.0;
ELSE
    cmdRaw := baseAir + airTrim;
    IF cmdRaw < 0.0 THEN
        airCommand := 0.0;
    ELSIF cmdRaw > 100.0 THEN
        airCommand := 100.0;
    ELSE
        airCommand := cmdRaw;
    END_IF;
END_IF;

prevReset := resetBtn;

END_FUNCTION_BLOCK
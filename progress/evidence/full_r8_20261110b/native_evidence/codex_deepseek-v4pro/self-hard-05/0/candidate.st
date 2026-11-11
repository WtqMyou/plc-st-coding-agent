FUNCTION_BLOCK FB
VAR_INPUT
    runRequest : BOOL;
    flameOK    : BOOL;
    o2Valid    : BOOL;
    o2PV       : REAL;
    baseAir    : REAL;
    resetBtn   : BOOL;
END_VAR
VAR_OUTPUT
    fuelPermit  : BOOL;
    trimEnable  : BOOL;
    airTrim     : REAL;
    airCommand  : REAL;
    tripLatched : BOOL;
    o2Fault     : BOOL;
END_VAR
VAR
    resetPrev   : BOOL;
    resetRising : BOOL;
    rawTrim     : REAL;
    rawCommand  : REAL;
END_VAR

resetRising := resetBtn AND NOT resetPrev;

IF runRequest AND NOT flameOK THEN
    tripLatched := TRUE;
ELSIF tripLatched AND resetRising AND NOT runRequest AND NOT flameOK THEN
    tripLatched := FALSE;
ELSE
    tripLatched := tripLatched;
END_IF

fuelPermit := runRequest AND flameOK AND NOT tripLatched;

o2Fault := (NOT o2Valid) OR (o2PV < 0.0) OR (o2PV > 21.0);

trimEnable := fuelPermit AND NOT o2Fault;

IF trimEnable THEN
    rawTrim := 2.0 * (2.0 - o2PV);
    IF rawTrim < -10.0 THEN
        airTrim := -10.0;
    ELSIF rawTrim > 10.0 THEN
        airTrim := 10.0;
    ELSE
        airTrim := rawTrim;
    END_IF
ELSE
    airTrim := 0.0;
END_IF

IF fuelPermit THEN
    rawCommand := baseAir + airTrim;
    IF rawCommand < 0.0 THEN
        airCommand := 0.0;
    ELSIF rawCommand > 100.0 THEN
        airCommand := 100.0;
    ELSE
        airCommand := rawCommand;
    END_IF
ELSE
    airCommand := 0.0;
END_IF

resetPrev := resetBtn;

END_FUNCTION_BLOCK
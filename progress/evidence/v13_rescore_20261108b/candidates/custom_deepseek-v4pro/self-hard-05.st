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
    resetPrev : BOOL := FALSE;
    resRising : BOOL;
    tripState : BOOL := FALSE;
    trimRaw : REAL;
    airCmdRaw : REAL;
END_VAR

resRising := resetBtn AND NOT resetPrev;

IF runRequest AND NOT flameOK THEN
    tripState := TRUE;
ELSE
    IF resRising AND NOT runRequest AND NOT flameOK THEN
        tripState := FALSE;
    END_IF;
END_IF;

resetPrev := resetBtn;

tripLatched := tripState;

o2Fault := (NOT o2Valid) OR (o2PV < 0.0) OR (o2PV > 21.0);

fuelPermit := runRequest AND flameOK AND NOT tripState;

trimEnable := fuelPermit AND NOT o2Fault;

IF trimEnable THEN
    trimRaw := 2.0 * (2.0 - o2PV);
    IF trimRaw > 10.0 THEN
        trimRaw := 10.0;
    ELSIF trimRaw < -10.0 THEN
        trimRaw := -10.0;
    END_IF;
    airTrim := trimRaw;
ELSE
    airTrim := 0.0;
END_IF;

airCmdRaw := baseAir + airTrim;
IF airCmdRaw > 100.0 THEN
    airCmdRaw := 100.0;
ELSIF airCmdRaw < 0.0 THEN
    airCmdRaw := 0.0;
END_IF;

IF NOT fuelPermit THEN
    airCmdRaw := 0.0;
END_IF;

airCommand := airCmdRaw;

END_FUNCTION_BLOCK
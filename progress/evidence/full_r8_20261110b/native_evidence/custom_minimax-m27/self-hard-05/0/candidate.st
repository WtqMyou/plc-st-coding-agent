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
    fuelPermit   : BOOL;
    trimEnable   : BOOL;
    airTrim      : REAL;
    airCommand   : REAL;
    tripLatched  : BOOL;
    o2Fault      : BOOL;
END_VAR
VAR
    tripLatchedState : BOOL := FALSE;
    prevResetBtn     : BOOL := FALSE;
    tempRaw          : REAL;
END_VAR

(* Trip latch logic *)
IF runRequest AND NOT flameOK THEN
    tripLatchedState := TRUE;
ELSIF NOT runRequest AND NOT flameOK AND resetBtn AND NOT prevResetBtn THEN
    tripLatchedState := FALSE;
END_IF

prevResetBtn := resetBtn;

tripLatched := tripLatchedState;

(* Fuel permit *)
fuelPermit := runRequest AND flameOK AND NOT tripLatchedState;

(* O2 fault detection *)
o2Fault := NOT o2Valid OR o2PV < 0.0 OR o2PV > 21.0;

(* Trim enable *)
trimEnable := fuelPermit AND NOT o2Fault;

(* Air trim calculation *)
IF trimEnable THEN
    tempRaw := 2.0 * (2.0 - o2PV);
    IF tempRaw > 10.0 THEN
        airTrim := 10.0;
    ELSIF tempRaw < -10.0 THEN
        airTrim := -10.0;
    ELSE
        airTrim := tempRaw;
    END_IF;
ELSE
    airTrim := 0.0;
END_IF;

(* Air command *)
IF fuelPermit THEN
    airCommand := baseAir + airTrim;
    IF airCommand > 100.0 THEN
        airCommand := 100.0;
    ELSIF airCommand < 0.0 THEN
        airCommand := 0.0;
    END_IF;
ELSE
    airCommand := 0.0;
END_IF;

END_FUNCTION_BLOCK
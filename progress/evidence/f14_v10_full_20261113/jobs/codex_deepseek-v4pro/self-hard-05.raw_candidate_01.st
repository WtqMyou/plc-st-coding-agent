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
    tmp_prevReset : BOOL := FALSE;
    tmp_trip : BOOL := FALSE;
    tmp_resetRising : BOOL;
    tmp_rawTrim : REAL;
    tmp_airSum : REAL;
END_VAR

(* ENGINEERING_CONTRACT
   tripLatched: activation runRequest AND NOT flameOK same scan; self-holding;
   reset only rising resetBtn when NOT runRequest AND NOT flameOK; activation wins same-scan reset.
   fuelPermit: runRequest AND flameOK AND NOT tripLatched, not latched.
   o2Fault: NOT o2Valid OR o2PV < 0.0 OR o2PV > 21.0, cuts trim but never fuel.
   trimEnable: fuelPermit AND NOT o2Fault, same scan.
   airTrim: 2.0*(2.0-o2PV), clamp [-10.0,10.0]; zero when trim disabled.
   airCommand: baseAir+airTrim clamp [0.0,100.0]; zero when no fuel permit.
   baseAir itself is unbounded; only final airCommand is bounded. Cite S1-S17/PUB001-PUB065.
*)

(* CONTRACT_RULES [] *)

tmp_resetRising := resetBtn AND NOT tmp_prevReset;

tmp_trip := (runRequest AND NOT flameOK)
            OR (tmp_trip AND NOT (tmp_resetRising AND NOT runRequest AND NOT flameOK));
tripLatched := tmp_trip;
tmp_prevReset := resetBtn;

fuelPermit := runRequest AND flameOK AND NOT tripLatched;

o2Fault := (NOT o2Valid) OR (o2PV < 0.0) OR (o2PV > 21.0);
trimEnable := fuelPermit AND NOT o2Fault;

tmp_rawTrim := 2.0 * (2.0 - o2PV);
IF tmp_rawTrim < -10.0 THEN
    airTrim := -10.0;
ELSIF tmp_rawTrim > 10.0 THEN
    airTrim := 10.0;
ELSE
    airTrim := tmp_rawTrim;
END_IF;

IF NOT trimEnable THEN
    airTrim := 0.0;
END_IF;

IF fuelPermit THEN
    tmp_airSum := baseAir + airTrim;
    IF tmp_airSum < 0.0 THEN
        airCommand := 0.0;
    ELSIF tmp_airSum > 100.0 THEN
        airCommand := 100.0;
    ELSE
        airCommand := tmp_airSum;
    END_IF;
ELSE
    airCommand := 0.0;
END_IF;

END_FUNCTION_BLOCK
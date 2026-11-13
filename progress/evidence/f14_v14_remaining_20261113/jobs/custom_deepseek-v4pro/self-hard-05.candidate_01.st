(* ENGINEERING_CONTRACT
tripLatched: set same scan when runRequest=TRUE AND flameOK=FALSE; held; clear only on rising resetBtn while runRequest=FALSE AND flameOK=FALSE; fire-set dominates. PUB001 PUB006 PUB030 PUB031 PUB059.
fuelPermit: combinational = runRequest AND flameOK AND NOT tripLatched. PUB005 PUB060.
o2Fault: combinational = NOT o2Valid OR o2PV<0.0 OR o2PV>21.0. PUB012 PUB061.
trimEnable: combinational = fuelPermit AND NOT o2Fault. PUB008 PUB061.
airTrim: if trimEnable then clamp(2.0*(2.0-o2PV), -10.0, 10.0) else 0.0; saturation reaches -10 only when o2PV>7.0. PUB010 PUB011 PUB014 PUB015 PUB052 PUB053.
airCommand: if fuelPermit then clamp(baseAir+airTrim, 0.0, 100.0) else 0.0. PUB011 PUB013 PUB015 PUB045 PUB046 PUB055.
reset edge: detected once per scan via prevResetBtn; no timer. Units: REAL %, BOOL, scan cycle. PUB006 PUB030 PUB031.
*)
(* CONTRACT_RULES [] *)
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
    prevResetBtn : BOOL := FALSE;
    tmp_resetRise : BOOL;
    tmp_prevTrip : BOOL;
    tmp_rawTrim : REAL;
    tmp_sum : REAL;
END_VAR

    tmp_resetRise := resetBtn AND NOT prevResetBtn;
    tmp_prevTrip := tripLatched;
    tripLatched := (runRequest AND NOT flameOK)
                   OR (tmp_prevTrip AND NOT (tmp_resetRise AND NOT runRequest AND NOT flameOK));
    prevResetBtn := resetBtn;

    fuelPermit := runRequest AND flameOK AND NOT tripLatched;

    o2Fault := (NOT o2Valid) OR (o2PV < 0.0) OR (o2PV > 21.0);
    trimEnable := fuelPermit AND NOT o2Fault;

    IF trimEnable THEN
        tmp_rawTrim := 2.0 * (2.0 - o2PV);
        IF tmp_rawTrim < -10.0 THEN
            airTrim := -10.0;
        ELSIF tmp_rawTrim > 10.0 THEN
            airTrim := 10.0;
        ELSE
            airTrim := tmp_rawTrim;
        END_IF;
    ELSE
        airTrim := 0.0;
    END_IF;

    IF fuelPermit THEN
        tmp_sum := baseAir + airTrim;
        IF tmp_sum < 0.0 THEN
            airCommand := 0.0;
        ELSIF tmp_sum > 100.0 THEN
            airCommand := 100.0;
        ELSE
            airCommand := tmp_sum;
        END_IF;
    ELSE
        airCommand := 0.0;
    END_IF;

END_FUNCTION_BLOCK
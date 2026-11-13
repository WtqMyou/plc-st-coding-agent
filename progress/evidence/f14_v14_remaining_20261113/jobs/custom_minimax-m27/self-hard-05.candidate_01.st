(* ENGINEERING_CONTRACT
1. tripLatched: activation is runRequest AND NOT flameOK; the trip is set in the same scan (PUB001, PUB003, PUB031).
2. tripLatched retention: remains TRUE until a rising resetBtn edge while runRequest=FALSE AND flameOK=FALSE (PUB002, PUB005, PUB032).
3. Reset priority: the safety-state rising edge clears an existing trip; an invalid reset edge has no effect (PUB032).
4. fuelPermit: combinational from runRequest, flameOK, and NOT tripLatched; no fuel is permitted while tripped (PUB003, PUB004, PUB007).
5. trimEnable/airTrim: active only with fuelPermit and no analyzer fault; trim is clamped to [-10,+10] (PUB009, PUB010, PUB011).
6. o2Fault: combinational analyzer validity/range fault; it removes trim only and never removes fuelPermit (PUB008, PUB012).
7. airCommand: fuelPermit permits the command; otherwise it is 0.0; permitted values are clamped to [0,100] (PUB006, PUB013, PUB014).
8. All outputs are sampled at scan end; no startup, purge, ignition, or BMS sequencing is included (PUB015).
9. Units: o2PV and air values are percent; airTrim limits are output bounds, not guaranteed reachable trim values.
10. Unspecified startup sequencing and external baseAir validity are not added as interlocks.
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
    tmp_resetPrev : BOOL := FALSE;
    tmp_resetRising : BOOL;
    tmp_rawTrim : REAL;
    tmp_rawCommand : REAL;
END_VAR

tmp_resetRising := resetBtn AND NOT tmp_resetPrev;

IF runRequest AND NOT flameOK THEN
    tripLatched := TRUE;
ELSIF tripLatched AND tmp_resetRising AND NOT runRequest AND NOT flameOK THEN
    tripLatched := FALSE;
END_IF;

tmp_resetPrev := resetBtn;

fuelPermit := runRequest AND flameOK AND NOT tripLatched;

o2Fault := NOT o2Valid OR o2PV < 0.0 OR o2PV > 21.0;
trimEnable := fuelPermit AND NOT o2Fault;

IF trimEnable THEN
    tmp_rawTrim := 2.0 * (2.0 - o2PV);
    IF tmp_rawTrim > 10.0 THEN
        airTrim := 10.0;
    ELSIF tmp_rawTrim < -10.0 THEN
        airTrim := -10.0;
    ELSE
        airTrim := tmp_rawTrim;
    END_IF;
ELSE
    airTrim := 0.0;
END_IF;

IF fuelPermit THEN
    tmp_rawCommand := baseAir + airTrim;
    IF tmp_rawCommand > 100.0 THEN
        airCommand := 100.0;
    ELSIF tmp_rawCommand < 0.0 THEN
        airCommand := 0.0;
    ELSE
        airCommand := tmp_rawCommand;
    END_IF;
ELSE
    airCommand := 0.0;
END_IF;

END_FUNCTION_BLOCK
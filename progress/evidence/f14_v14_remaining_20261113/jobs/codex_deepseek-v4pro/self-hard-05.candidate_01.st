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
    local_resetEdge : R_TRIG;
    tmp_resetRising : BOOL;
    tmp_rawTrim : REAL;
    tmp_rawAir : REAL;
END_VAR

(* ENGINEERING_CONTRACT
tripLatched: set same scan when runRequest & !flameOK; holds; reset only resetBtn rising with !runRequest & !flameOK (PUB001/PUB002).
fuelPermit: runRequest & flameOK & !tripLatched, evaluated after trip update (PUB003).
o2Fault: !o2Valid OR o2PV<0.0 OR o2PV>21.0; combinational, does not cut fuel (PUB005).
trimEnable: fuelPermit & !o2Fault; combinational after fuel/fault update (PUB004/PUB008).
airTrim: if trimEnable then clamp(2.0*(2.0-o2PV),-10.0,10.0), else 0.0; units % (PUB004/PUB006).
airCommand: if fuelPermit then clamp(baseAir+airTrim,0.0,100.0), else 0.0; baseAir itself not bounded (PUB006).
R_TRIG evaluated before state equations; held resetBtn has no repeated effect; units: o2PV/baseAir/airTrim/airCommand %.
*)
(* CONTRACT_RULES [] *)

local_resetEdge(CLK := resetBtn);
tmp_resetRising := local_resetEdge.Q;

tripLatched := (runRequest AND NOT flameOK)
    OR (tripLatched AND NOT (tmp_resetRising AND NOT runRequest AND NOT flameOK));

fuelPermit := runRequest AND flameOK AND NOT tripLatched;

o2Fault := (NOT o2Valid) OR (o2PV < 0.0) OR (o2PV > 21.0);

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
    tmp_rawAir := baseAir + airTrim;
    IF tmp_rawAir > 100.0 THEN
        airCommand := 100.0;
    ELSIF tmp_rawAir < 0.0 THEN
        airCommand := 0.0;
    ELSE
        airCommand := tmp_rawAir;
    END_IF;
ELSE
    airCommand := 0.0;
END_IF;

END_FUNCTION_BLOCK
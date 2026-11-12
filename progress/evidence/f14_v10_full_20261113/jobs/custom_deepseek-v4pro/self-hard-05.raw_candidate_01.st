(* ENGINEERING_CONTRACT
   tripLatched: set same-scan on runRequest AND NOT flameOK; held until reset rising edge
                with runRequest=FALSE AND flameOK=FALSE only. Same-scan set/reset mutually exclusive.
   fuelPermit : runRequest AND flameOK AND NOT tripLatched; computed after trip update.
   trimEnable : fuelPermit AND NOT o2Fault.
   airTrim    : trimEnable ? clamp(2.0*(2.0-o2PV), -10.0, 10.0) : 0.0; REAL percent.
   airCommand : fuelPermit ? clamp(baseAir+airTrim, 0.0, 100.0) : 0.0; REAL percent.
   o2Fault    : NOT o2Valid OR o2PV<0.0 OR o2PV>21.0; combinational.
*)
(* CONTRACT_RULES [] *)
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
    fbResetEdge     : R_TRIG;
    tmp_resetRising : BOOL;
    tmp_trim        : REAL;
    tmp_cmd         : REAL;
END_VAR

fbResetEdge(CLK := resetBtn);
tmp_resetRising := fbResetEdge.Q;

(* Trip latch: same-scan loss-of-flame set; only valid safe-state reset edge clears. *)
tripLatched := (runRequest AND NOT flameOK)
               OR (tripLatched AND NOT (tmp_resetRising AND NOT runRequest AND NOT flameOK));

(* Oxygen analyzer fault and permits. *)
o2Fault := (NOT o2Valid) OR (o2PV < 0.0) OR (o2PV > 21.0);
fuelPermit := runRequest AND flameOK AND NOT tripLatched;
trimEnable := fuelPermit AND NOT o2Fault;

(* Oxygen trim with +/-10 percent output clamp. *)
IF trimEnable THEN
    tmp_trim := 2.0 * (2.0 - o2PV);
    IF tmp_trim < -10.0 THEN
        tmp_trim := -10.0;
    ELSIF tmp_trim > 10.0 THEN
        tmp_trim := 10.0;
    END_IF;
    airTrim := tmp_trim;
ELSE
    airTrim := 0.0;
END_IF;

(* Final air command with 0..100 percent output clamp. *)
IF fuelPermit THEN
    tmp_cmd := baseAir + airTrim;
    IF tmp_cmd < 0.0 THEN
        tmp_cmd := 0.0;
    ELSIF tmp_cmd > 100.0 THEN
        tmp_cmd := 100.0;
    END_IF;
    airCommand := tmp_cmd;
ELSE
    airCommand := 0.0;
END_IF;

END_FUNCTION_BLOCK
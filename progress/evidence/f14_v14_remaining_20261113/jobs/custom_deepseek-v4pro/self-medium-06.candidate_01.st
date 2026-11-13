FUNCTION_BLOCK FB
VAR_INPUT
    enable: BOOL;
    resetBtn: BOOL;
    sensorValid: BOOL;
    setpoint: REAL;
    temperature: REAL;
    scanSeconds: REAL;
    bias: REAL;
END_VAR
VAR_OUTPUT
    power: REAL;
    correction: REAL;
    fault: BOOL;
END_VAR
VAR
    ePrev: REAL := 0.0;
    histValid: BOOL := FALSE;
    resetRTrig: R_TRIG;
    resetEdge: BOOL;
    e: REAL;
    x: REAL;
    y: REAL;
    de: REAL;
END_VAR

(* ENGINEERING_CONTRACT
   - fault (PUB004/PUB032/S4): combinational from sensorValid and scanSeconds; no retention; updated every scan.
   - power/correction: combinational outputs from current inputs and internal history; not latched except zero-clear on !enable/fault/reset rise.
   - Clear on !enable OR fault OR resetBtn rising edge (PUB005): same scan, zero outputs and clear history (ePrev=0, histValid=false); reset edge is one-shot.
   - Valid first/cleared-history scan (PUB005): de=0, correction=20*clamp(e/10, -1, 1); equivalent to y=0.
   - Valid with previous history (PUB004/PUB006): de=(e-ePrev)/scanSeconds; y=clamp(de/2,-1,1); correction=20*x+10*y (S13 equivalence).
   - power = LIMIT(0, bias+correction, 100) (PUB005/S1/S10); correction within ±30 by construction.
   - Units: temp °C, scan seconds s, bias/power/correction %, e/10 and de/2 dimensionless.
   - History update: after any valid computation, ePrev=e, histValid=true; otherwise reset.
   - Same-scan priority: clear condition dominates computation.
*)
(* CONTRACT_RULES [] *)

fault := (NOT sensorValid) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

resetRTrig(CLK := resetBtn);
resetEdge := resetRTrig.Q;

IF (NOT enable) OR fault OR resetEdge THEN
    power := 0.0;
    correction := 0.0;
    ePrev := 0.0;
    histValid := FALSE;
ELSE
    e := setpoint - temperature;
    x := LIMIT(-1.0, e / 10.0, 1.0);
    
    IF NOT histValid THEN
        de := 0.0;
        y := 0.0;
        correction := 20.0 * x;
    ELSE
        de := (e - ePrev) / scanSeconds;
        y := LIMIT(-1.0, de / 2.0, 1.0);
        correction := 20.0 * x + 10.0 * y;
    END_IF;
    
    power := LIMIT(0.0, bias + correction, 100.0);
    
    histValid := TRUE;
    ePrev := e;
END_IF;

END_FUNCTION_BLOCK
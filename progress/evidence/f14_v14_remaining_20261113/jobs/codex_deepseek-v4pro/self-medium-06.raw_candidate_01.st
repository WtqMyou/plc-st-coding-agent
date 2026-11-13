FUNCTION_BLOCK FB
VAR_INPUT
    enable : BOOL;
    resetBtn : BOOL;
    sensorValid : BOOL;
    setpoint : REAL;
    temperature : REAL;
    scanSeconds : REAL;
    bias : REAL;
END_VAR
VAR_OUTPUT
    power : REAL;
    correction : REAL;
    fault : BOOL;
END_VAR
VAR
    tmp_e : REAL;
    tmp_de : REAL;
    tmp_x : REAL;
    tmp_y : REAL;
    tmp_ePrev : REAL := 0.0;
    tmp_historyValid : BOOL := FALSE;
    tmp_resetEdge : R_TRIG;
    tmp_resetPulse : BOOL;
END_VAR

(* CONTRACT_RULES [] *)

(* ENGINEERING_CONTRACT
   power: active only enable & !fault & no reset pulse; zero branch has same-scan priority; recomputed/clamped each active scan; 0..100.
   correction: computed on active scan; zero branch resets; first/cleared-history scan uses de=0; range [-30,30]; no separate clamp.
   fault: combinational from !sensorValid or scanSeconds<=0 or scanSeconds>10.
   reset: R_TRIG pulse only; held reset does not sustain zero.
   history: ePrev and historyValid retained; cleared in every zero branch; set after active computation.
   units: e degC, de degC/s, scanSeconds s, bias/power/correction %.
   derivation: 9-rule product centroid algebraically equals 20x+10y with history, 20x on first/cleared-history scan.
*)

tmp_resetEdge(CLK := resetBtn);
tmp_resetPulse := tmp_resetEdge.Q;

fault := (NOT sensorValid) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

IF (NOT enable) OR fault OR tmp_resetPulse THEN
    power := 0.0;
    correction := 0.0;
    tmp_ePrev := 0.0;
    tmp_historyValid := FALSE;
ELSE
    tmp_e := setpoint - temperature;

    IF NOT tmp_historyValid THEN
        tmp_de := 0.0;
    ELSE
        tmp_de := (tmp_e - tmp_ePrev) / scanSeconds;
    END_IF;

    tmp_x := LIMIT(-1.0, tmp_e / 10.0, 1.0);
    tmp_y := LIMIT(-1.0, tmp_de / 2.0, 1.0);

    IF NOT tmp_historyValid THEN
        correction := 20.0 * tmp_x;
    ELSE
        correction := 20.0 * tmp_x + 10.0 * tmp_y;
    END_IF;

    tmp_ePrev := tmp_e;
    tmp_historyValid := TRUE;

    power := LIMIT(0.0, bias + correction, 100.0);
END_IF;

END_FUNCTION_BLOCK
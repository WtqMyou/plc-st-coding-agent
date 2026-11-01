FUNCTION_BLOCK FB
VAR_INPUT
 enable : BOOL;
 resetBtn : BOOL;
 sensorValid : BOOL;
 setpoint : REAL;
 temperature : REAL;
 dt : REAL;
 bias : REAL;
END_VAR
VAR_OUTPUT
 power : REAL;
 correction : REAL;
 fault : BOOL;
END_VAR
VAR
 prevReset : BOOL;
 prevE : REAL;
 hasHist : BOOL;
 eNow : REAL;
 eDe : REAL;
 xx : REAL;
 yy : REAL;
 mx : REAL;
 zx : REAL;
 px : REAL;
 my : REAL;
 zy : REAL;
 py : REAL;
 wsum : REAL;
 wc : REAL;
 cOut : REAL;
 edgeReset : BOOL;
END_VAR
fault := (NOT sensorValid) OR (dt <= 0.0) OR (dt > 10.0);
edgeReset := resetBtn AND NOT prevReset;
IF edgeReset OR (NOT enable) OR fault THEN
 cOut := 0.0;
 hasHist := FALSE;
 prevE := 0.0;
ELSE
 eNow := setpoint - temperature;
 IF hasHist THEN
  eDe := (eNow - prevE) / dt;
 ELSE
  eDe := 0.0;
 END_IF;
 xx := eNow / 10.0;
 IF xx > 1.0 THEN xx := 1.0; END_IF;
 IF xx < -1.0 THEN xx := -1.0; END_IF;
 yy := eDe / 2.0;
 IF yy > 1.0 THEN yy := 1.0; END_IF;
 IF yy < -1.0 THEN yy := -1.0; END_IF;
 mx := MAX(-xx, 0.0);
 zx := 1.0 - ABS(xx);
 px := MAX(xx, 0.0);
 my := MAX(-yy, 0.0);
 zy := 1.0 - ABS(yy);
 py := MAX(yy, 0.0);
 wsum := mx * my + mx * zy + mx * py + zx * my + zx * zy + zx * py
  + px * my + px * zy + px * py;
 wc := mx * my * (-30.0) + mx * zy * (-20.0) + mx * py * (-10.0)
  + zx * my * (-10.0) + zx * zy * 0.0 + zx * py * 10.0
  + px * my * 10.0 + px * zy * 20.0 + px * py * 30.0;
 IF wsum > 0.0 THEN
  cOut := wc / wsum;
 ELSE
  cOut := 0.0;
 END_IF;
 prevE := eNow;
 hasHist := TRUE;
END_IF;
prevReset := resetBtn;
correction := cOut;
IF edgeReset OR (NOT enable) OR fault THEN
 power := 0.0;
ELSE
 power := bias + cOut;
 IF power > 100.0 THEN power := 100.0; END_IF;
 IF power < 0.0 THEN power := 0.0; END_IF;
END_IF;
END_FUNCTION_BLOCK

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
    power : REAL := 0.0;
    correction : REAL := 0.0;
    fault : BOOL := FALSE;
END_VAR

VAR
    ePrev : REAL := 0.0;
    hasHistory : BOOL := FALSE;
    prevEnableAndNoFault : BOOL := FALSE;
    prevResetBtn : BOOL := FALSE;
END_VAR

VAR
    risingReset : BOOL;
    e : REAL;
    de : REAL;
    x : REAL;
    y : REAL;
    muNx : REAL;
    muZx : REAL;
    muPx : REAL;
    muNy : REAL;
    muZy : REAL;
    muPy : REAL;
    w1 : REAL;
    w2 : REAL;
    w3 : REAL;
    w4 : REAL;
    w5 : REAL;
    w6 : REAL;
    w7 : REAL;
    w8 : REAL;
    w9 : REAL;
    sumW : REAL;
    sumWc : REAL;
END_VAR

risingReset := resetBtn AND NOT prevResetBtn;
fault := NOT sensorValid OR scanSeconds <= 0.0 OR scanSeconds > 10.0;

IF fault OR risingReset OR NOT enable THEN
    ePrev := 0.0;
    hasHistory := FALSE;
END_IF;

IF scanSeconds <= 0.0 OR scanSeconds > 10.0 OR NOT sensorValid THEN
    power := 0.0;
    correction := 0.0;
    prevEnableAndNoFault := enable AND NOT fault;
    prevResetBtn := resetBtn;
    RETURN;
END_IF;

e := setpoint - temperature;

IF NOT hasHistory THEN
    de := 0.0;
ELSE
    de := (e - ePrev) / scanSeconds;
END_IF;

x := LIMIT(-1.0, e / 10.0, 1.0);
y := LIMIT(-1.0, de / 2.0, 1.0);

muNx := MAX(-x, 0.0);
muZx := 1.0 - ABS(x);
muPx := MAX(x, 0.0);

muNy := MAX(-y, 0.0);
muZy := 1.0 - ABS(y);
muPy := MAX(y, 0.0);

w1 := muNx * muNy;
w2 := muNx * muZy;
w3 := muNx * muPy;
w4 := muZx * muNy;
w5 := muZx * muZy;
w6 := muZx * muPy;
w7 := muPx * muNy;
w8 := muPx * muZy;
w9 := muPx * muPy;

sumW := w1 + w2 + w3 + w4 + w5 + w6 + w7 + w8 + w9;
sumWc := w1 * (-30.0) + w2 * (-20.0) + w3 * (-10.0) + w4 * (-10.0) + w5 * 0.0 + w6 * 10.0 + w7 * 10.0 + w8 * 20.0 + w9 * 30.0;

IF sumW > 0.0 THEN
    correction := sumWc / sumW;
ELSE
    correction := 0.0;
END_IF;

power := LIMIT(0.0, bias + correction, 100.0);

hasHistory := TRUE;
ePrev := e;
prevEnableAndNoFault := enable AND NOT fault;
prevResetBtn := resetBtn;
END_FUNCTION_BLOCK
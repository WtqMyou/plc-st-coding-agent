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
    ePrev : REAL := 0.0;
    historyValid : BOOL := FALSE;
    prevResetBtn : BOOL := FALSE;
    e : REAL;
    de : REAL;
    x : REAL;
    y : REAL;
    muN_x : REAL;
    muZ_x : REAL;
    muP_x : REAL;
    muN_y : REAL;
    muZ_y : REAL;
    muP_y : REAL;
    sumW : REAL;
    sumWC : REAL;
    risingReset : BOOL;
END_VAR

fault := NOT sensorValid OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);
risingReset := resetBtn AND NOT prevResetBtn;
e := setpoint - temperature;

IF (NOT enable) OR fault OR risingReset THEN
    power := 0.0;
    correction := 0.0;
    ePrev := 0.0;
    historyValid := FALSE;
ELSE
    IF historyValid THEN
        de := (e - ePrev) / scanSeconds;
    ELSE
        de := 0.0;
    END_IF;

    x := e / 10.0;
    IF x < -1.0 THEN
        x := -1.0;
    ELSIF x > 1.0 THEN
        x := 1.0;
    END_IF;

    y := de / 2.0;
    IF y < -1.0 THEN
        y := -1.0;
    ELSIF y > 1.0 THEN
        y := 1.0;
    END_IF;

    muN_x := MAX(-x, 0.0);
    muZ_x := 1.0 - ABS(x);
    muP_x := MAX(x, 0.0);

    muN_y := MAX(-y, 0.0);
    muZ_y := 1.0 - ABS(y);
    muP_y := MAX(y, 0.0);

    sumW := (muN_x * muN_y) + (muN_x * muZ_y) + (muN_x * muP_y)
          + (muZ_x * muN_y) + (muZ_x * muZ_y) + (muZ_x * muP_y)
          + (muP_x * muN_y) + (muP_x * muZ_y) + (muP_x * muP_y);

    sumWC := (muN_x * muN_y * (-30.0)) + (muN_x * muZ_y * (-20.0)) + (muN_x * muP_y * (-10.0))
           + (muZ_x * muN_y * (-10.0)) + (muZ_x * muZ_y * 0.0) + (muZ_x * muP_y * 10.0)
           + (muP_x * muN_y * 10.0) + (muP_x * muZ_y * 20.0) + (muP_x * muP_y * 30.0);

    IF sumW = 0.0 THEN
        correction := 0.0;
    ELSE
        correction := sumWC / sumW;
    END_IF;

    power := LIMIT(0.0, bias + correction, 100.0);

    ePrev := e;
    historyValid := TRUE;
END_IF;

prevResetBtn := resetBtn;

END_FUNCTION_BLOCK
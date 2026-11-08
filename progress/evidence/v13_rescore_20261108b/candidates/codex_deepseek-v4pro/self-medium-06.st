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
    resetPrev : BOOL;
    resetRising : BOOL;
    ePrev : REAL;
    bHist : BOOL;
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
    w : REAL;
    num : REAL;
    den : REAL;
    rawPower : REAL;
END_VAR

resetRising := resetBtn AND NOT resetPrev;
resetPrev := resetBtn;

fault := (NOT sensorValid) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

IF (NOT enable) OR resetRising OR fault THEN
    power := 0.0;
    correction := 0.0;
    ePrev := 0.0;
    bHist := FALSE;
ELSE
    e := setpoint - temperature;

    IF bHist THEN
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

    muNx := -x;
    IF muNx < 0.0 THEN
        muNx := 0.0;
    END_IF;

    IF x >= 0.0 THEN
        muZx := 1.0 - x;
    ELSE
        muZx := 1.0 + x;
    END_IF;

    muPx := x;
    IF muPx < 0.0 THEN
        muPx := 0.0;
    END_IF;

    muNy := -y;
    IF muNy < 0.0 THEN
        muNy := 0.0;
    END_IF;

    IF y >= 0.0 THEN
        muZy := 1.0 - y;
    ELSE
        muZy := 1.0 + y;
    END_IF;

    muPy := y;
    IF muPy < 0.0 THEN
        muPy := 0.0;
    END_IF;

    num := 0.0;
    den := 0.0;

    w := muNx;
    IF muNy < w THEN
        w := muNy;
    END_IF;
    num := num + w * (-30.0);
    den := den + w;

    w := muNx;
    IF muZy < w THEN
        w := muZy;
    END_IF;
    num := num + w * (-20.0);
    den := den + w;

    w := muNx;
    IF muPy < w THEN
        w := muPy;
    END_IF;
    num := num + w * (-10.0);
    den := den + w;

    w := muZx;
    IF muNy < w THEN
        w := muNy;
    END_IF;
    num := num + w * (-10.0);
    den := den + w;

    w := muZx;
    IF muZy < w THEN
        w := muZy;
    END_IF;
    num := num + w * 0.0;
    den := den + w;

    w := muZx;
    IF muPy < w THEN
        w := muPy;
    END_IF;
    num := num + w * 10.0;
    den := den + w;

    w := muPx;
    IF muNy < w THEN
        w := muNy;
    END_IF;
    num := num + w * 10.0;
    den := den + w;

    w := muPx;
    IF muZy < w THEN
        w := muZy;
    END_IF;
    num := num + w * 20.0;
    den := den + w;

    w := muPx;
    IF muPy < w THEN
        w := muPy;
    END_IF;
    num := num + w * 30.0;
    den := den + w;

    IF den > 0.0 THEN
        correction := num / den;
    ELSE
        correction := 0.0;
    END_IF;

    rawPower := bias + correction;
    IF rawPower < 0.0 THEN
        power := 0.0;
    ELSIF rawPower > 100.0 THEN
        power := 100.0;
    ELSE
        power := rawPower;
    END_IF;

    ePrev := e;
    bHist := TRUE;
END_IF;

END_FUNCTION_BLOCK
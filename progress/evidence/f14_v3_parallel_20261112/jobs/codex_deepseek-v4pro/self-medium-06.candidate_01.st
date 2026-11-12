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
    resetPrev : BOOL := FALSE;
    resetRising : BOOL;
    e : REAL;
    de : REAL;
    x : REAL;
    y : REAL;
END_VAR

resetRising := resetBtn AND NOT resetPrev;
fault := (NOT sensorValid) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

IF (NOT enable) OR fault OR resetRising THEN
    power := 0.0;
    correction := 0.0;
    ePrev := 0.0;
    historyValid := FALSE;
ELSE
    e := setpoint - temperature;

    IF NOT historyValid THEN
        de := 0.0;
    ELSE
        de := (e - ePrev) / scanSeconds;
    END_IF;

    x := LIMIT(-1.0, e / 10.0, 1.0);
    y := LIMIT(-1.0, de / 2.0, 1.0);

    correction := 20.0 * x + 10.0 * y;
    power := LIMIT(0.0, bias + correction, 100.0);

    ePrev := e;
    historyValid := TRUE;
END_IF;

resetPrev := resetBtn;

END_FUNCTION_BLOCK
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
    lastReset : BOOL;
    ePrev : REAL;
    historyValid : BOOL;
    resetRising : BOOL;
    e : REAL;
    de : REAL;
    x : REAL;
    y : REAL;
END_VAR

fault := (NOT sensorValid) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);
resetRising := resetBtn AND (NOT lastReset);

IF (NOT enable) OR fault OR resetRising THEN
    power := 0.0;
    correction := 0.0;
    ePrev := 0.0;
    historyValid := FALSE;
ELSE
    e := setpoint - temperature;
    x := LIMIT(-1.0, e / 10.0, 1.0);

    IF historyValid THEN
        de := (e - ePrev) / scanSeconds;
    ELSE
        de := 0.0;
    END_IF;

    y := LIMIT(-1.0, de / 2.0, 1.0);
    correction := 20.0 * x + 10.0 * y;
    power := LIMIT(0.0, bias + correction, 100.0);

    ePrev := e;
    historyValid := TRUE;
END_IF;

lastReset := resetBtn;
END_FUNCTION_BLOCK
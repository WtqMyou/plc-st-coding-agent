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
    histValid : BOOL;
    ePrev : REAL;
    e : REAL;
    de : REAL;
    x : REAL;
    y : REAL;
    uxN : REAL;
    uxZ : REAL;
    uxP : REAL;
    uyN : REAL;
    uyZ : REAL;
    uyP : REAL;
    wSum : REAL;
    wcSum : REAL;
    resetRising : BOOL;
    forceZero : BOOL;
END_VAR

    fault := (NOT sensorValid) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);
    resetRising := resetBtn AND (NOT lastReset);
    forceZero := (NOT enable) OR fault OR resetRising;

    IF forceZero THEN
        power := 0.0;
        correction := 0.0;
        histValid := FALSE;
        ePrev := 0.0;
    ELSE
        e := setpoint - temperature;
        IF histValid THEN
            de := (e - ePrev) / scanSeconds;
        ELSE
            de := 0.0;
        END_IF

        x := LIMIT(-1.0, e / 10.0, 1.0);
        y := LIMIT(-1.0, de / 2.0, 1.0);

        uxN := MAX(-x, 0.0);
        uxZ := 1.0 - ABS(x);
        uxP := MAX(x, 0.0);
        uyN := MAX(-y, 0.0);
        uyZ := 1.0 - ABS(y);
        uyP := MAX(y, 0.0);

        wSum := uxN * uyN + uxN * uyZ + uxN * uyP
              + uxZ * uyN + uxZ * uyZ + uxZ * uyP
              + uxP * uyN + uxP * uyZ + uxP * uyP;
        wcSum := uxN * uyN * (-30.0)
               + uxN * uyZ * (-20.0)
               + uxN * uyP * (-10.0)
               + uxZ * uyN * (-10.0)
               + uxZ * uyZ * 0.0
               + uxZ * uyP * 10.0
               + uxP * uyN * 10.0
               + uxP * uyZ * 20.0
               + uxP * uyP * 30.0;

        IF wSum > 0.0 THEN
            correction := wcSum / wSum;
        ELSE
            correction := 0.0;
        END_IF

        power := LIMIT(0.0, bias + correction, 100.0);

        ePrev := e;
        histValid := TRUE;
    END_IF

    lastReset := resetBtn;

END_FUNCTION_BLOCK
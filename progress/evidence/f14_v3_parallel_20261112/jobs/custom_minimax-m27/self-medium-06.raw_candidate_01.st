FUNCTION_BLOCK FB
VAR_INPUT
    enable         : BOOL;
    resetBtn       : BOOL;
    sensorValid    : BOOL;
    setpoint       : REAL;
    temperature    : REAL;
    scanSeconds    : REAL;
    bias           : REAL;
END_VAR
VAR_OUTPUT
    power          : REAL;
    correction     : REAL;
    fault          : BOOL;
END_VAR
VAR
    ePrev          : REAL := 0.0;
    historyFirst   : BOOL := FALSE;
    resetPrev      : BOOL := FALSE;
END_VAR
VAR_TEMP
    e              : REAL;
    de             : REAL;
    xNorm          : REAL;
    yNorm          : REAL;
    muNx           : REAL;
    muZx           : REAL;
    muPx           : REAL;
    muNy           : REAL;
    muZy           : REAL;
    muPy           : REAL;
    wNN            : REAL;
    wNZ            : REAL;
    wNP            : REAL;
    wZN            : REAL;
    wZZ            : REAL;
    wZP            : REAL;
    wPN            : REAL;
    wPZ            : REAL;
    wPP            : REAL;
    sumW           : REAL;
    sumWC          : REAL;
    risingReset    : BOOL;
    firstScan      : BOOL;
END_VAR
BEGIN
    risingReset := resetBtn AND NOT resetPrev;
    resetPrev   := resetBtn;

    fault := NOT sensorValid OR scanSeconds <= 0.0 OR scanSeconds > 10.0;

    IF NOT enable OR fault OR risingReset THEN
        power       := 0.0;
        correction  := 0.0;
        ePrev       := 0.0;
        historyFirst := FALSE;
    ELSE
        e := setpoint - temperature;

        IF NOT historyFirst THEN
            de := 0.0;
        ELSE
            de := (e - ePrev) / scanSeconds;
        END_IF;

        xNorm := LIMIT(-1.0, e / 10.0, 1.0);
        yNorm := LIMIT(-1.0, de / 2.0, 1.0);

        muNx := MAX(-xNorm, 0.0);
        muZx := MAX(1.0 - ABS(xNorm), 0.0);
        muPx := MAX(xNorm, 0.0);

        muNy := MAX(-yNorm, 0.0);
        muZy := MAX(1.0 - ABS(yNorm), 0.0);
        muPy := MAX(yNorm, 0.0);

        wNN := muNx * muNy;
        wNZ := muNx * muZy;
        wNP := muNx * muPy;
        wZN := muZx * muNy;
        wZZ := muZx * muZy;
        wZP := muZx * muPy;
        wPN := muPx * muNy;
        wPZ := muPx * muZy;
        wPP := muPx * muPy;

        sumW := wNN + wNZ + wNP + wZN + wZZ + wZP + wPN + wPZ + wPP;

        sumWC := wNN * (-30.0)
               + wNZ * (-20.0)
               + wNP * (-10.0)
               + wZN * (-10.0)
               + wZZ *   0.0
               + wZP *  10.0
               + wPN *  10.0
               + wPZ *  20.0
               + wPP *  30.0;

        IF sumW > 0.0 THEN
            correction := sumWC / sumW;
        ELSE
            correction := 0.0;
        END_IF;

        power := LIMIT(0.0, bias + correction, 100.0);

        firstScan := NOT historyFirst;
        ePrev := e;
        historyFirst := TRUE;
    END_IF;
END_FUNCTION_BLOCK
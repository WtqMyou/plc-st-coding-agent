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
    ePrev : REAL;
    hasHistory : BOOL;
    e : REAL;
    de : REAL;
    x : REAL;
    y : REAL;
    muNX : REAL;
    muZX : REAL;
    muPX : REAL;
    muNY : REAL;
    muZY : REAL;
    muPY : REAL;
    wNN : REAL;
    wNZ : REAL;
    wNP : REAL;
    wZN : REAL;
    wZZ : REAL;
    wZP : REAL;
    wPN : REAL;
    wPZ : REAL;
    wPP : REAL;
    sumW : REAL;
    sumWC : REAL;
    resetRising : BOOL;
    clearHistory : BOOL;
END_VAR

fault := NOT sensorValid OR scanSeconds <= 0.0 OR scanSeconds > 10.0;
resetRising := resetBtn AND NOT resetPrev;
clearHistory := NOT enable OR fault OR resetRising;

IF clearHistory THEN
    power := 0.0;
    correction := 0.0;
    ePrev := 0.0;
    hasHistory := FALSE;
ELSE
    e := setpoint - temperature;
    IF hasHistory THEN
        de := (e - ePrev) / scanSeconds;
    ELSE
        de := 0.0;
    END_IF

    x := e / 10.0;
    IF x < -1.0 THEN
        x := -1.0;
    ELSIF x > 1.0 THEN
        x := 1.0;
    END_IF

    y := de / 2.0;
    IF y < -1.0 THEN
        y := -1.0;
    ELSIF y > 1.0 THEN
        y := 1.0;
    END_IF

    IF x < 0.0 THEN
        muNX := -x;
    ELSE
        muNX := 0.0;
    END_IF
    muZX := 1.0 - ABS(x);
    IF x > 0.0 THEN
        muPX := x;
    ELSE
        muPX := 0.0;
    END_IF

    IF y < 0.0 THEN
        muNY := -y;
    ELSE
        muNY := 0.0;
    END_IF
    muZY := 1.0 - ABS(y);
    IF y > 0.0 THEN
        muPY := y;
    ELSE
        muPY := 0.0;
    END_IF

    wNN := muNX * muNY;
    wNZ := muNX * muZY;
    wNP := muNX * muPY;
    wZN := muZX * muNY;
    wZZ := muZX * muZY;
    wZP := muZX * muPY;
    wPN := muPX * muNY;
    wPZ := muPX * muZY;
    wPP := muPX * muPY;

    sumW := wNN + wNZ + wNP + wZN + wZZ + wZP + wPN + wPZ + wPP;
    IF sumW > 0.0 THEN
        sumWC := wNN * (-30.0) + wNZ * (-20.0) + wNP * (-10.0)
               + wZN * (-10.0) + wZZ * 0.0 + wZP * 10.0
               + wPN * 10.0 + wPZ * 20.0 + wPP * 30.0;
        correction := sumWC / sumW;
    ELSE
        correction := 0.0;
    END_IF

    IF correction < -30.0 THEN
        correction := -30.0;
    ELSIF correction > 30.0 THEN
        correction := 30.0;
    END_IF

    power := bias + correction;
    IF power < 0.0 THEN
        power := 0.0;
    ELSIF power > 100.0 THEN
        power := 100.0;
    END_IF

    ePrev := e;
    hasHistory := TRUE;
END_IF

resetPrev := resetBtn;
END_FUNCTION_BLOCK
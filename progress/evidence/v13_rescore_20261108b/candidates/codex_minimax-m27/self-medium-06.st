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
    firstScan      : BOOL := TRUE;
    resetBtnPrev   : BOOL := FALSE;
    
    e              : REAL;
    de             : REAL;
    x              : REAL;
    y              : REAL;
    
    muN_x          : REAL;
    muZ_x          : REAL;
    muP_x          : REAL;
    muN_y          : REAL;
    muZ_y          : REAL;
    muP_y          : REAL;
    
    w1             : REAL;
    w2             : REAL;
    w3             : REAL;
    w4             : REAL;
    w5             : REAL;
    w6             : REAL;
    w7             : REAL;
    w8             : REAL;
    w9             : REAL;
    
    sum_w          : REAL;
    sum_wc         : REAL;
    raw_power      : REAL;
END_VAR

fault := NOT sensorValid OR scanSeconds <= 0.0 OR scanSeconds > 10.0;

IF NOT enable OR (resetBtn AND NOT resetBtnPrev AND NOT fault) OR fault THEN
    power := 0.0;
    correction := 0.0;
    ePrev := 0.0;
    firstScan := TRUE;
END_IF

resetBtnPrev := resetBtn;

IF enable AND NOT fault THEN
    e := setpoint - temperature;
    
    IF firstScan THEN
        de := 0.0;
        firstScan := FALSE;
    ELSE
        de := (e - ePrev) / scanSeconds;
    END_IF
    
    ePrev := e;
    
    IF e > 10.0 THEN
        x := 1.0;
    ELSIF e < -10.0 THEN
        x := -1.0;
    ELSE
        x := e / 10.0;
    END_IF
    
    IF de > 2.0 THEN
        y := 1.0;
    ELSIF de < -2.0 THEN
        y := -1.0;
    ELSE
        y := de / 2.0;
    END_IF
    
    muN_x := -x;
    IF muN_x < 0.0 THEN muN_x := 0.0; END_IF
    
    muZ_x := 1.0 - ABS(x);
    IF muZ_x < 0.0 THEN muZ_x := 0.0; END_IF
    
    muP_x := x;
    IF muP_x < 0.0 THEN muP_x := 0.0; END_IF
    
    muN_y := -y;
    IF muN_y < 0.0 THEN muN_y := 0.0; END_IF
    
    muZ_y := 1.0 - ABS(y);
    IF muZ_y < 0.0 THEN muZ_y := 0.0; END_IF
    
    muP_y := y;
    IF muP_y < 0.0 THEN muP_y := 0.0; END_IF
    
    w1 := muN_x * muN_y;
    w2 := muN_x * muZ_y;
    w3 := muN_x * muP_y;
    w4 := muZ_x * muN_y;
    w5 := muZ_x * muZ_y;
    w6 := muZ_x * muP_y;
    w7 := muP_x * muN_y;
    w8 := muP_x * muZ_y;
    w9 := muP_x * muP_y;
    
    sum_w := w1 + w2 + w3 + w4 + w5 + w6 + w7 + w8 + w9;
    sum_wc := w1 * (-30.0) + w2 * (-20.0) + w3 * (-10.0) + 
              w4 * (-10.0) + w5 * 0.0 + w6 * 10.0 + 
              w7 * 10.0 + w8 * 20.0 + w9 * 30.0;
    
    IF sum_w > 0.0 THEN
        correction := sum_wc / sum_w;
    ELSE
        correction := 0.0;
    END_IF
    
    raw_power := bias + correction;
    
    IF raw_power < 0.0 THEN
        power := 0.0;
    ELSIF raw_power > 100.0 THEN
        power := 100.0;
    ELSE
        power := raw_power;
    END_IF
ELSE
    power := 0.0;
    correction := 0.0;
END_IF

END_FUNCTION_BLOCK
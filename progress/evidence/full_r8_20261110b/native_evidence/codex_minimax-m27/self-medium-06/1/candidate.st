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
    histCleared    : BOOL := FALSE;
    prevResetBtn   : BOOL := FALSE;
    prevEnable     : BOOL := FALSE;
    prevFault      : BOOL := FALSE;
    risingReset    : BOOL;
    e              : REAL;
    de             : REAL;
    x              : REAL;
    y              : REAL;
    muNx           : REAL;
    muZx           : REAL;
    muPx           : REAL;
    muNy           : REAL;
    muZy           : REAL;
    muPy           : REAL;
    w              : ARRAY[1..3, 1..3] OF REAL;
    sumWC          : REAL;
    sumW           : REAL;
END_VAR

// Fault detection
fault := NOT sensorValid OR scanSeconds <= 0.0 OR scanSeconds > 10.0;

// Edge detection for reset
risingReset := resetBtn AND NOT prevResetBtn;

// Update history state for next cycle
prevResetBtn := resetBtn;
prevEnable := enable;
prevFault := fault;

// Handle clearing conditions
IF fault OR NOT enable OR risingReset THEN
    power := 0.0;
    correction := 0.0;
    ePrev := 0.0;
    histCleared := FALSE;
ELSE
    // Normal operation
    e := setpoint - temperature;
    
    // Determine if this is a "first run" after clear
    IF NOT histCleared THEN
        de := 0.0;
        histCleared := TRUE;
    ELSE
        IF scanSeconds > 0.0 THEN
            de := (e - ePrev) / scanSeconds;
        ELSE
            de := 0.0;
        END_IF
    END_IF;
    
    // Normalize e to x
    IF e / 10.0 > 1.0 THEN
        x := 1.0;
    ELSIF e / 10.0 < -1.0 THEN
        x := -1.0;
    ELSE
        x := e / 10.0;
    END_IF;
    
    // Normalize de to y
    IF de / 2.0 > 1.0 THEN
        y := 1.0;
    ELSIF de / 2.0 < -1.0 THEN
        y := -1.0;
    ELSE
        y := de / 2.0;
    END_IF;
    
    // Membership functions for x
    IF x < 0.0 THEN
        muNx := -x;
    ELSE
        muNx := 0.0;
    END_IF;
    muZx := 1.0 - ABS(x);
    IF x > 0.0 THEN
        muPx := x;
    ELSE
        muPx := 0.0;
    END_IF;
    
    // Membership functions for y
    IF y < 0.0 THEN
        muNy := -y;
    ELSE
        muNy := 0.0;
    END_IF;
    muZy := 1.0 - ABS(y);
    IF y > 0.0 THEN
        muPy := y;
    ELSE
        muPy := 0.0;
    END_IF;
    
    // Calculate weights for 9 rules (row=x, col=y)
    // N×N=-30
    w[1, 1] := muNx * muNy;
    // N×Z=-20
    w[1, 2] := muNx * muZy;
    // N×P=-10
    w[1, 3] := muNx * muPy;
    // Z×N=-10
    w[2, 1] := muZx * muNy;
    // Z×Z=0
    w[2, 2] := muZx * muZy;
    // Z×P=10
    w[2, 3] := muZx * muPy;
    // P×N=10
    w[3, 1] := muPx * muNy;
    // P×Z=20
    w[3, 2] := muPx * muZy;
    // P×P=30
    w[3, 3] := muPx * muPy;
    
    // Center of gravity defuzzification
    sumWC := w[1,1]*(-30.0) + w[1,2]*(-20.0) + w[1,3]*(-10.0) +
             w[2,1]*(-10.0) + w[2,2]*0.0      + w[2,3]*10.0   +
             w[3,1]*10.0   + w[3,2]*20.0      + w[3,3]*30.0;
    sumW := w[1,1] + w[1,2] + w[1,3] +
            w[2,1] + w[2,2] + w[2,3] +
            w[3,1] + w[3,2] + w[3,3];
    
    IF sumW > 0.0 THEN
        correction := sumWC / sumW;
    ELSE
        correction := 0.0;
    END_IF;
    
    // Clamp power to 0..100
    IF bias + correction > 100.0 THEN
        power := 100.0;
    ELSIF bias + correction < 0.0 THEN
        power := 0.0;
    ELSE
        power := bias + correction;
    END_IF;
    
    // Store error for next cycle
    ePrev := e;
END_IF;
END_FUNCTION_BLOCK
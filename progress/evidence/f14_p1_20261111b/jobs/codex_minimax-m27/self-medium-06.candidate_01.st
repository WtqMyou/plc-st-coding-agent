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
    power      : REAL;
    correction : REAL;
    fault      : BOOL;
END_VAR

VAR
    ePrev       : REAL := 0.0;
    hasHistory  : BOOL := FALSE;
    prevResetBtn : BOOL := FALSE;
END_VAR

// Temp vars
VAR
    e, de, x, y         : REAL;
    muNx, muZx, muPx    : REAL;
    muNy, muZy, muPy    : REAL;
    w_NN, w_NZ, w_NP    : REAL;
    w_ZN, w_ZZ, w_ZP    : REAL;
    w_PN, w_PZ, w_PP    : REAL;
    sumWc, sumW         : REAL;
    resetRising         : BOOL;
END_VAR

// Fault detection
fault := (NOT sensorValid) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

// Rising edge of resetBtn
resetRising := resetBtn AND (NOT prevResetBtn);
prevResetBtn := resetBtn;

// Clear outputs and history on disable, fault, or reset rising edge
IF (NOT enable) OR fault OR resetRising THEN
    power      := 0.0;
    correction := 0.0;
    ePrev      := 0.0;
    hasHistory := FALSE;
ELSE
    // Calculate error
    e := setpoint - temperature;

    // Calculate derivative of error
    // First scan after history cleared: de = 0
    IF hasHistory THEN
        de := (e - ePrev) / scanSeconds;
    ELSE
        de := 0.0;
    END_IF;

    // Normalize error and derivative
    // x range: [-1, 1] for e in [-10, 10] degC
    // y range: [-1, 1] for de in [-2, 2] degC/s
    x := e / 10.0;
    IF x > 1.0 THEN x := 1.0; END_IF;
    IF x < -1.0 THEN x := -1.0; END_IF;

    y := de / 2.0;
    IF y > 1.0 THEN y := 1.0; END_IF;
    IF y < -1.0 THEN y := -1.0; END_IF;

    // Membership functions for x (error)
    muNx := -x;
    IF muNx < 0.0 THEN muNx := 0.0; END_IF;
    muZx := 1.0 - ABS(x);
    muPx := x;
    IF muPx < 0.0 THEN muPx := 0.0; END_IF;

    // Membership functions for y (derivative)
    muNy := -y;
    IF muNy < 0.0 THEN muNy := 0.0; END_IF;
    muZy := 1.0 - ABS(y);
    muPy := y;
    IF muPy < 0.0 THEN muPy := 0.0; END_IF;

    // Rule weights: w(i,j) = mu_i(x) * mu_j(y)
    w_NN := muNx * muNy;  // N x N
    w_NZ := muNx * muZy;  // N x Z
    w_NP := muNx * muPy;  // N x P
    w_ZN := muZx * muNy;  // Z x N
    w_ZZ := muZx * muZy;  // Z x Z
    w_ZP := muZx * muPy;  // Z x P
    w_PN := muPx * muNy;  // P x N
    w_PZ := muPx * muZy;  // P x Z
    w_PP := muPx * muPy;  // P x P

    // Centroid defuzzification
    // Single-point outputs: NxN=-30, NxZ=-20, NxP=-10,
    //                       ZxN=-10, ZxZ=0,   ZxP=10,
    //                       PxN=10,  PxZ=20,  PxP=30
    sumWc := w_NN * (-30.0) + w_NZ * (-20.0) + w_NP * (-10.0)
           + w_ZN * (-10.0) + w_ZZ * 0.0     + w_ZP * 10.0
           + w_PN * 10.0     + w_PZ * 20.0    + w_PP * 30.0;
    sumW := w_NN + w_NZ + w_NP + w_ZN + w_ZZ + w_ZP + w_PN + w_PZ + w_PP;

    IF sumW > 0.0 THEN
        correction := sumWc / sumW;
    ELSE
        correction := 0.0;
    END_IF;

    // Power: bias + correction, clamped to [0, 100]
    power := bias + correction;
    IF power > 100.0 THEN power := 100.0; END_IF;
    IF power < 0.0 THEN power := 0.0; END_IF;

    // Update history for next scan
    ePrev := e;
    hasHistory := TRUE;
END_IF

END_FUNCTION_BLOCK
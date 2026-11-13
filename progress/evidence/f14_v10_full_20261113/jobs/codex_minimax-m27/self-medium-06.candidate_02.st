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
    prevResetBtn   : BOOL := FALSE;
    prevEnable     : BOOL := FALSE;
    prevFault      : BOOL := FALSE;
    ePrev          : REAL := 0.0;
    historyCleared : BOOL := TRUE;
END_VAR

(* CONTRACT_RULES [] *)

(*
ENGINEERING_CONTRACT:
| Output/State  | Activation          | Retention       | Reset/Deactivation    | Same-Scan Priority | Units/Boundaries |
|---------------|---------------------|-----------------|-----------------------|--------------------|------------------|
| power         | enable & !fault     | Last valid      | !enable / fault /     | power=0 overrides  | 0..100 %         |
|               | & !resetRisingEdge  | clamp(bias+corr)| resetRisingEdge       | normal calc        |                  |
| correction    | enable & !fault     | Last valid      | !enable / fault /     | correction=0       | -30..30 %        |
|               | & !resetRisingEdge  | (no clamp)      | resetRisingEdge       | overrides calc     |                  |
| fault         | !sensorValid OR     | Latched while   | sensorValid & valid   | N/A (combinational)| BOOLEAN          |
|               | scanSeconds<=0/>10  | condition holds | scanSeconds           |                    |                  |
| ePrev         | Cleared on          | Holds across    | Cleared on !enable /  | N/A                | ℃               |
|               | first valid scan    | scans           | fault / resetRising   |                    |                  |
| historyCleared| Set TRUE on clear   | FALSE otherwise | Set TRUE on clear     | N/A                | BOOLEAN          |
| PUB001: enable controls autonomous mode
| PUB004: resetBtn is rising-edge command
| PUB006: fault triggers output zero + history clear
| PUB010: correction is centroid defuzzified
| PUB014: power = clamp(bias+correction, 0, 100)
*)
VAR
    resetRisingEdge : BOOL;
    e               : REAL;
    de              : REAL;
    x               : REAL;
    y               : REAL;
    muN_x           : REAL;
    muZ_x           : REAL;
    muP_x           : REAL;
    muN_y           : REAL;
    muZ_y           : REAL;
    muP_y           : REAL;
    wNN, wNZ, wNP   : REAL;
    wZN, wZZ, wZP   : REAL;
    wPN, wPZ, wPP   : REAL;
    sumW            : REAL;
    sumWc           : REAL;
END_VAR

// Fault detection (PUB006/PUB032)
fault := NOT sensorValid OR scanSeconds <= 0.0 OR scanSeconds > 10.0;

// Rising edge detection for resetBtn
resetRisingEdge := resetBtn AND NOT prevResetBtn;

// Clearing logic: first valid scan after disable/fault/reset rising edge
IF (NOT prevEnable OR resetRisingEdge OR prevFault) THEN
    power := 0.0;
    correction := 0.0;
    ePrev := 0.0;
    historyCleared := TRUE;
END_IF;

// Main computation when enabled and not faulted
IF enable AND NOT fault THEN
    // Compute error (PUB001)
    e := setpoint - temperature;
    
    // Compute derivative (PUB002/PUB003)
    IF historyCleared THEN
        de := 0.0;
    ELSE
        de := (e - ePrev) / scanSeconds;
    END_IF;
    
    // Normalize inputs (PUB005)
    x := LIMIT(-1.0, e / 10.0, 1.0);
    y := LIMIT(-1.0, de / 2.0, 1.0);
    
    // Membership functions (PUB004)
    muN_x := MAX(-x, 0.0);
    muZ_x := MAX(1.0 - ABS(x), 0.0);
    muP_x := MAX(x, 0.0);
    
    muN_y := MAX(-y, 0.0);
    muZ_y := MAX(1.0 - ABS(y), 0.0);
    muP_y := MAX(y, 0.0);
    
    // Rule weights: w(i,j) = mu_i(x) * mu_j(y)
    wNN := muN_x * muN_y;
    wNZ := muN_x * muZ_y;
    wNP := muN_x * muP_y;
    wZN := muZ_x * muN_y;
    wZZ := muZ_x * muZ_y;
    wZP := muZ_x * muP_y;
    wPN := muP_x * muN_y;
    wPZ := muP_x * muZ_y;
    wPP := muP_x * muP_y;
    
    // Centroid defuzzification (PUB010)
    sumW  := wNN + wNZ + wNP + wZN + wZZ + wZP + wPN + wPZ + wPP;
    sumWc := wNN * (-30.0) + wNZ * (-20.0) + wNP * (-10.0)
           + wZN * (-10.0) + wZZ * 0.0    + wZP * 10.0
           + wPN * 10.0   + wPZ * 20.0    + wPP * 30.0;
    
    IF sumW > 0.0 THEN
        correction := sumWc / sumW;
    ELSE
        correction := 0.0;
    END_IF;
    
    // Output with clamping (PUB014)
    power := LIMIT(0.0, bias + correction, 100.0);
    
    // Update history for next scan
    ePrev := e;
    historyCleared := FALSE;
END_IF;

// Update previous values for next scan
prevResetBtn := resetBtn;
prevEnable := enable;
prevFault := fault;
END_FUNCTION_BLOCK
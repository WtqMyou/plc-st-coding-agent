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
    ePrev              : REAL := 0.0;
    prevEnableAndNotFault : BOOL := FALSE;
    prevResetBtn       : BOOL := FALSE;
    historyValid       : BOOL := FALSE;
    temp_e             : REAL;
    temp_de            : REAL;
    x                  : REAL;
    y                  : REAL;
    xN, xZ, xP         : REAL;
    yN, yZ, yP         : REAL;
    wNN, wNZ, wNP      : REAL;
    wZN, wZZ, wZP      : REAL;
    wPN, wPZ, wPP      : REAL;
    wSum               : REAL;
END_VAR
(* ENGINEERING_CONTRACT
+-------------------------------------------------------------------------------------+
| Output/State Group  | Activation           | Retention   | Reset/Deactivation     |
+-------------------------------------------------------------------------------------+
| power (0..100%)     | enable & !fault &    | bias+corr   | fault|!enable|reset↑   |
|                     | !rising(resetBtn)    | clamped     | (first scan only)      |
+-------------------------------------------------------------------------------------+
| correction (±30%)   | enable & !fault &    | Σ(w·c)/Σw  | fault|!enable|reset↑   |
|                     | !rising(resetBtn)    | (centroid)  | (first scan only)      |
+-------------------------------------------------------------------------------------+
| ePrev (history)     | normal differential  | held        | fault|!enable|reset↑   |
|                     | on valid non-first   | across scan | clears to 0.0          |
|                     | scans                |             |                        |
+-------------------------------------------------------------------------------------+
| de (error deriv.)   | de=0 on first scan;  | N/A         | N/A                    |
|                     | de=(e-ePrev)/scanSec |             |                        |
|                     | on valid non-first   |             |                        |
+-------------------------------------------------------------------------------------+
| fault               | !sensorValid OR      | latched     | NOT modelled (output)  |
|                     | scanSeconds<=0 OR    | until clear |                        |
|                     | scanSeconds>10       |             |                        |
+-------------------------------------------------------------------------------------+
| PUB reference: PUB001=enable, PUB002=resetBtn↑, PUB003=sensorValid, PUB004=setpoint|
|                PUB005=temperature, PUB006=scanSeconds (s), PUB007=bias             |
|                PUB008=power[0,100], PUB009=correction, PUB010=fault conditions     |
|                PUB011-015=reset behavior, PUB016-020=first-scan de=0               |
+-------------------------------------------------------------------------------------+
*)
    // Fault detection: PUB010
    fault := NOT sensorValid OR scanSeconds <= 0.0 OR scanSeconds > 10.0;

    // Clear outputs and history on fault, disable, or reset rising edge: PUB011, PUB012
    IF fault OR NOT enable OR (resetBtn AND NOT prevResetBtn) THEN
        power := 0.0;
        correction := 0.0;
        ePrev := 0.0;
        historyValid := FALSE;
        // Do not update prev* here; preserve for next-scan rising detection
    ELSE
        temp_e := setpoint - temperature;

            // First scan after clear: de = 0; PUB017, PUB020
            IF NOT (prevEnableAndNotFault AND NOT (resetBtn AND NOT prevResetBtn)) THEN
                // First scan or history was cleared
                temp_de := 0.0;
                historyValid := FALSE;
            ELSE
                // Normal differential: PUB019
                IF scanSeconds > 0.0 THEN
                    temp_de := (temp_e - ePrev) / scanSeconds;
                ELSE
                    temp_de := 0.0;
                END_IF;
                historyValid := TRUE;
            END_IF;

            // Normalize: x = clamp(e/10, -1, 1), y = clamp(de/2, -1, 1); PUB005
            x := temp_e / 10.0;
            IF x > 1.0 THEN x := 1.0; ELSIF x < -1.0 THEN x := -1.0; END_IF;
            y := temp_de / 2.0;
            IF y > 1.0 THEN y := 1.0; ELSIF y < -1.0 THEN y := -1.0; END_IF;

            // Membership functions: μN(z)=max(-z,0), μZ(z)=1-|z|, μP(z)=max(z,0); PUB003
            xN := 0.0; IF x < 0.0 THEN xN := -x; END_IF;
            xZ := 1.0 - ABS(x); IF xZ < 0.0 THEN xZ := 0.0; END_IF;
            xP := 0.0; IF x > 0.0 THEN xP := x; END_IF;

            yN := 0.0; IF y < 0.0 THEN yN := -y; END_IF;
            yZ := 1.0 - ABS(y); IF yZ < 0.0 THEN yZ := 0.0; END_IF;
            yP := 0.0; IF y > 0.0 THEN yP := y; END_IF;

            // Rule weights: w(i,j) = μi(x) × μj(y); PUB004
            wNN := xN * yN;
            wNZ := xN * yZ;
            wNP := xN * yP;
            wZN := xZ * yN;
            wZZ := xZ * yZ;
            wZP := xZ * yP;
            wPN := xP * yN;
            wPZ := xP * yZ;
            wPP := xP * yP;

            // Centroid defuzzification: correction = Σ(w·c)/Σw; PUB004
            wSum := wNN + wNZ + wNP + wZN + wZZ + wZP + wPN + wPZ + wPP;
            IF wSum > 0.0 THEN
                correction := (wNN * (-30.0) + wNZ * (-20.0) + wNP * (-10.0) +
                               wZN * (-10.0) + wZZ *   0.0 + wZP *   10.0 +
                               wPN *  10.0 + wPZ *   20.0 + wPP *   30.0) / wSum;
            ELSE
                correction := 0.0;
            END_IF;

            // Update ePrev for next scan: PUB018
        ePrev := temp_e;
        power := bias + correction;
        IF power > 100.0 THEN power := 100.0;
        ELSIF power < 0.0 THEN power := 0.0;
        END_IF;
    END_IF;

    // Update state tracking for next scan; PUB002 (rising edge detection)
    prevEnableAndNotFault := enable AND NOT fault;
    prevResetBtn := resetBtn;
END_FUNCTION_BLOCK
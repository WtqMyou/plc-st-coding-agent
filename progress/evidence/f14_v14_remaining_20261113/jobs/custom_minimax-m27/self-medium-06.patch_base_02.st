(* ENGINEERING_CONTRACT FB_FuzzyTempControl
   ========================================================================
   Outputs & State Retention:
   --------------------------------------------------------------------
   power:       COMBINATIONAL (bias + correction) clamped to [0,100].
                Zeroed on enable=FALSE, fault=TRUE, or resetBtn rising.
   correction:  COMBINATIONAL weighted-centroid per 9 rules.
                Zeroed same as power; no internal clamping (range ±30).
   fault:       COMBINATIONAL; fault = NOT sensorValid OR scanSeconds
                outside (0,10]. Not latched.
   ePrev:       RETAINED across scans; cleared on rising(resetBtn),
                enable=FALSE, or fault=TRUE.
   tmpHistValid:RETAINED; FALSE after clear, set TRUE after first de.
   tmpResetPrevHigh:RETAINED; set TRUE on rising(resetBtn), cleared
                next scan so held reset allows normal calculation.
   -----------------------------------------------------------------------
   First-scan rule (PUB011/PUB012): when tmpHistValid=FALSE, de=0.
   Subsequent scans use ePrev for differential calculation.
   Reset is edge-triggered only (rising edge clears; held reset allows
   normal fuzzy output per S9).
   ========================================================================
*)
FUNCTION_BLOCK FB
VAR
    ePrev          : REAL := 0.0;
    tmpHistValid   : BOOL := FALSE;
    tmpResetPrevHigh: BOOL := FALSE;
END_VAR
VAR_OUTPUT
    power      : REAL;
    correction : REAL;
    fault      : BOOL;
END_VAR
VAR_INPUT
    enable      : BOOL;
    resetBtn    : BOOL;
    sensorValid : BOOL;
    setpoint    : REAL;
    temperature : REAL;
    scanSeconds : REAL;
    bias        : REAL;
END_VAR

    (* --- Fault determination (PUB004, PUB028) --- *)
    fault := NOT sensorValid OR scanSeconds <= 0.0 OR scanSeconds > 10.0;

    (* --- Reset rising-edge detection (PUB011): edge only, not hold --- *)
    IF resetBtn AND NOT tmpResetPrevHigh THEN
        (* Rising edge of resetBtn this scan: zero outputs, clear history --- *)
        power       := 0.0;
        correction  := 0.0;
        ePrev       := 0.0;
        tmpHistValid := FALSE;
        tmpResetPrevHigh := TRUE;
        RETURN;
    END_IF;

    (* Remember current resetBtn for next-scan edge detection --- *)
    tmpResetPrevHigh := resetBtn;

    (* --- Disabled or faulted: zero outputs, clear history (PUB011) --- *)
    IF NOT enable OR fault THEN
        power       := 0.0;
        correction  := 0.0;
        ePrev       := 0.0;
        tmpHistValid := FALSE;
        RETURN;
    END_IF;

    (* ==================================================================
       Normal fuzzy calculation
       ================================================================== *)
    VAR
        e          : REAL;
        de         : REAL;
        x          : REAL;
        y          : REAL;
        muN_x      : REAL;
        muZ_x      : REAL;
        muP_x      : REAL;
        muN_y      : REAL;
        muZ_y      : REAL;
        muP_y      : REAL;
        w           : ARRAY[1..3, 1..3] OF REAL;
        sumW        : REAL;
        sumWc       : REAL;
        row         : INT;
        col         : INT;
        tmpFirstScan: BOOL;
    END_VAR

    (* PUB001: error definition --- *)
    e := setpoint - temperature;

    (* PUB012: first-scan detection --- *)
    tmpFirstScan := NOT tmpHistValid;

    (* PUB011: de = 0 on first scan or after history clear --- *)
    IF tmpFirstScan THEN
        de := 0.0;
    ELSE
        de := (e - ePrev) / scanSeconds;
    END_IF;

    (* PUB003 / PUB005: normalize to [-1,1] --- *)
    x := LIMIT(-1.0, e / 10.0, 1.0);
    y := LIMIT(-1.0, de / 2.0, 1.0);

    (* PUB006: membership functions --- *)
    muN_x := MAX(-x, 0.0);
    muZ_x := MAX(1.0 - ABS(x), 0.0);
    muP_x := MAX( x, 0.0);

    muN_y := MAX(-y, 0.0);
    muZ_y := MAX(1.0 - ABS(y), 0.0);
    muP_y := MAX( y, 0.0);

    (* Rule weights: row = x (N/Z/P), col = y (N/Z/P) --- *)
    w[1,1] := muN_x * muN_y;   (* N,N *)
    w[1,2] := muN_x * muZ_y;   (* N,Z *)
    w[1,3] := muN_x * muP_y;   (* N,P *)
    w[2,1] := muZ_x * muN_y;   (* Z,N *)
    w[2,2] := muZ_x * muZ_y;   (* Z,Z *)
    w[2,3] := muZ_x * muP_y;   (* Z,P *)
    w[3,1] := muP_x * muN_y;   (* P,N *)
    w[3,2] := muP_x * muZ_y;   (* P,Z *)
    w[3,3] := muP_x * muP_y;   (* P,P *)

    (* Weighted centroid (PUB007): sum(w*c)/sum(w) --- *)
    sumW  := 0.0;
    sumWc := 0.0;
    FOR row := 1 TO 3 DO
        FOR col := 1 TO 3 DO
            sumW  := sumW  + w[row, col];
            sumWc := sumWc + w[row, col] * SEL(INT_TO_INT(row - 1), SEL(INT_TO_INT(col - 1),
                                 -30.0,   (* row=1 (N) *)
                                 -10.0,   (* row=2 (Z) *)
                                  10.0),  (* row=3 (P) *)
                                 SEL(INT_TO_INT(col - 1),
                                 -20.0,   (* col=1 (N) *)
                                   0.0,   (* col=2 (Z) *)
                                  20.0)); (* col=3 (P) *)
        END_FOR;
    END_FOR;

    (* PUB007: Σw=0 → correction=0 --- *)
    IF sumW > 0.0 THEN
        correction := sumWc / sumW;
    ELSE
        correction := 0.0;
    END_IF;

    (* PUB008: power = clamp(bias + correction, 0, 100) --- *)
    power := LIMIT(0.0, bias + correction, 100.0);

    (* Update history for next scan --- *)
    ePrev       := e;
    tmpHistValid := TRUE;
END_FUNCTION_BLOCK
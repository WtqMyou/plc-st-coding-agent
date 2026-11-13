FUNCTION_BLOCK FB
VAR_INPUT
    enable        : BOOL;
    resetBtn      : BOOL;
    sensorValid   : BOOL;
    setpoint      : REAL;
    temperature   : REAL;
    scanSeconds   : REAL;
    bias          : REAL;
END_VAR
VAR_OUTPUT
    power         : REAL;
    correction    : REAL;
    fault         : BOOL;
END_VAR
VAR
    ePrev               : REAL := 0.0;
    firstOrCleared      : BOOL := FALSE;
    prev_enable         : BOOL := FALSE;
    prev_resetBtn       : BOOL := FALSE;
    prev_fault          : BOOL := FALSE;
    tmp_power           : REAL;
END_VAR
VAR_CONSTANT
    (* ENGINEERING_CONTRACT
     * Pub refs: PUB001-PUB054
     * Outputs:
     * - power: HOLD(0..100) across scans; latched by fault/enable/Ftrig(resetBtn) per PUB032,PUB042,PUB043
     * - correction: HOLD(±30) across scans; cleared same as power; NOT independently clamped per PUB036
     * - fault: combinational; set when NOT sensorValid OR scanSeconds<=0 OR scanSeconds>10 per PUB039-PUB040
     * State retention:
     * - ePrev, firstOrCleared held across scans (cleared on fault|!enable|rising(resetBtn) per PUB042-PUB043)
     * - After clear: firstOrCleared=TRUE only on that scan; next scan firstOrCleared=FALSE again
     * Priority: resetBtn rising edge (highest) > fault/enable OFF > normal computation per PUB042-PUB043
     * Units: e[℃], de[℃/s], x[-1..1], y[-1..1], correction[%], power[%]
     * Boundaries: e scale ±10℃, de scale ±2℃/s, correction range ±30, power range [0,100]
     * First-scan rule: de=0 when firstOrCleared=TRUE (PUB044-PUB046)
     * Sum-of-weights simplification: Σw=1 always for triangular membership, centroid reduces to 20x+10y
     *)
END_VAR

    (* Detect rising edge of resetBtn *)
    IF resetBtn AND NOT prev_resetBtn THEN
        (* PUB042: rising edge of resetBtn clears history and forces outputs to 0 on this scan *)
        ePrev          := 0.0;
        firstOrCleared := TRUE;
        power          := 0.0;
        correction     := 0.0;
    ELSIF (NOT enable) OR fault THEN
        (* PUB042: fault OR !enable also clears history *)
        ePrev          := 0.0;
        firstOrCleared := TRUE;
        power          := 0.0;
        correction     := 0.0;
    ELSIF prev_enable AND NOT prev_fault AND enable AND NOT fault AND firstOrCleared THEN
        (* Transition from fault/!enable -> enable&!fault with cleared history:
         * this scan is the "first/cleared" scan (firstOrCleared already TRUE from prior clear)
         * de = 0 per PUB044-PUB045; normal ePrev update suppressed; done below *)
        firstOrCleared := TRUE;
    ELSE
        (* Normal computation scan; ePrev will be updated *)
        firstOrCleared := FALSE;
    END_IF

    (* Fault combinational output per PUB039 *)
    fault := NOT sensorValid OR scanSeconds <= 0.0 OR scanSeconds > 10.0;

    (* Fuzzy computation when enable AND NOT fault *)
    IF enable AND NOT fault THEN
        (* Error and derivative *)
        VAR e, de : REAL; END_VAR
        e  := setpoint - temperature;
        IF firstOrCleared THEN
            (* PUB044-PUB045: first scan or post-clear scan uses de=0 *)
            de := 0.0;
        ELSE
            (* PUB044: normal derivative with stored ePrev *)
            de := (e - ePrev) / scanSeconds;
        END_IF;

        (* Normalized inputs *)
        VAR x, y : REAL; END_VAR
        x := LIMIT(-1.0, e / 10.0, 1.0);
        y := LIMIT(-1.0, de / 2.0, 1.0);

        (* Triangular membership functions: μN(z)=max(-z,0), μZ(z)=1-|z|, μP(z)=max(z,0) *)
        VAR muNx, muZx, muPx, muNy, muZy, muPy : REAL; END_VAR
        muNx := MAX(-x, 0.0);
        muZx := MAX(1.0 - ABS(x), 0.0);
        muPx := MAX( x, 0.0);
        muNy := MAX(-y, 0.0);
        muZy := MAX(1.0 - ABS(y), 0.0);
        muPy := MAX( y, 0.0);

        (* 9-rule weighted centroid: rule weights w(i,j)=μi(x)×μj(y), outputs per PUB006 *)
        (* N×N=-30, N×Z=-20, N×P=-10, Z×N=-10, Z×Z=0, Z×P=10, P×N=10, P×Z=20, P×P=30 *)
        VAR wSum : REAL; END_VAR
        wSum := (muNx + muZx + muPx) * (muNy + muZy + muPy);  (* always 1.0 *)
        IF wSum > 0.0 THEN
            correction := (
                -30.0 * muNx * muNy + -20.0 * muNx * muZy + -10.0 * muNx * muPy +
                -10.0 * muZx * muNy +   0.0 * muZx * muZy +  10.0 * muZx * muPy +
                 10.0 * muPx * muNy +  20.0 * muPx * muZy +  30.0 * muPx * muPy
            ) / wSum;
        ELSE
            correction := 0.0;
        END_IF;

        (* Power = clamp(bias + correction, 0, 100); correction itself NOT clamped per PUB036 *)
        tmp_power := bias + correction;
        power     := LIMIT(0.0, tmp_power, 100.0);

        (* Update ePrev for next scan (only on normal computation scans) *)
        ePrev := e;
    END_IF;

    (* Update edge-detection state for next scan *)
    prev_enable   := enable;
    prev_resetBtn := resetBtn;
    prev_fault    := fault;
END_FUNCTION_BLOCK

(* CONTRACT_RULES [] *)
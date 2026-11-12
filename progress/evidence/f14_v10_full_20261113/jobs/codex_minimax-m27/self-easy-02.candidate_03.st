FUNCTION_BLOCK FB
VAR_INPUT
    tankLevel   : REAL;
    outletFlow  : REAL;
    inletPermit : BOOL;
    resetBtn    : BOOL;
END_VAR
VAR_OUTPUT
    pumpRun        : BOOL;
    alarmHigh      : BOOL;
    alarmLow       : BOOL;
    outletValveOpen: BOOL;
END_VAR
VAR
    prevResetBtn : BOOL := FALSE;
END_VAR
(* ENGINEERING_CONTRACT *)
(* alarmHigh: SET at tankLevel>=85.0 (same-scan priority). HOLD until resetBtn rising AND tankLevel<85.0. RESET only when safe first. *)
(* alarmLow:  SET at tankLevel<=15.0 (same-scan priority). HOLD until resetBtn rising AND tankLevel>15.0. RESET only when safe first. *)
(* pumpRun:   ACT when inletPermit=TRUE AND alarmHigh=FALSE AND alarmLow=FALSE. STOP on any alarm or !inletPermit. *)
(* outletValveOpen: ON when alarmLow=FALSE. OFF when alarmLow=TRUE. No reset edge effect. *)
(* resetBtn:  Rising edge detection, firstScan=FALSE. Holding across level change does NOT re-trigger. *)
BEGIN
    (* Update alarmHigh *)
    IF tankLevel >= 85.0 THEN
        alarmHigh := TRUE;
    ELSIF resetBtn AND NOT prevResetBtn AND tankLevel < 85.0 THEN
        alarmHigh := FALSE;
    END_IF;

    (* Update alarmLow *)
    IF tankLevel <= 15.0 THEN
        alarmLow := TRUE;
    ELSIF resetBtn AND NOT prevResetBtn AND tankLevel > 15.0 THEN
        alarmLow := FALSE;
    END_IF;

    (* pumpRun: stop before start *)
    IF alarmHigh OR alarmLow OR NOT inletPermit THEN
        pumpRun := FALSE;
    ELSE
        pumpRun := TRUE;
    END_IF;

    (* outletValveOpen: inverse of alarmLow *)
    outletValveOpen := NOT alarmLow;

    (* Store previous state *)
    prevResetBtn := resetBtn;
END_FUNCTION_BLOCK
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FB
VAR_INPUT
    mode : INT;
    resetBtn : BOOL;
    scanSeconds : REAL;
    tempSP : REAL;
    tempPV : REAL;
    flowPV : REAL;
    manualFlowSP : REAL;
    manualValve : REAL;
END_VAR
VAR_OUTPUT
    flowSP : REAL;
    valveCommand : REAL;
    fault : BOOL;
    normalMode : BOOL;
END_VAR
VAR
    accT : REAL;
    accF : REAL;
    eT : REAL;
    eF : REAL;
    raw : REAL;
    local_hasPrev : BOOL;
    local_prevMode : INT;
    local_prevReset : BOOL;
    local_modeChanged : BOOL;
    local_resetEdge : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
   flowSP: bounded 0..50 t/h (S1). valveCommand: bounded 0..100 % (S2).
   fault: invalid mode/scanSeconds -> manual outputs, no PI, normalMode false (PUB006,S3,S10).
   reset edge: manual outputs, no PI, edge memory; hold does not repeat (PUB005,S4).
   transition: to mode 1/0 flowSP=manual and valve holds; to mode 2 both hold; normal false (PUB004,S7,S8).
   normalMode: prior scan exists, mode stable, no fault, no reset edge (S11).
   normal PI: cascade outer then inner; accT/accF back-calculated from clamped outputs (PUB003,S13,S14).
   manual normal: both outputs follow manual values (S5); auto flowSP=manual (S6).
   same-scan priority: reset > fault > first scan > mode change > normal; fault still reported on reset scan.
*)

(* CONTRACT_RULES [] *)

eT := tempSP - tempPV;

fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

local_resetEdge := resetBtn AND NOT local_prevReset;
local_modeChanged := local_hasPrev AND (mode <> local_prevMode);

IF local_resetEdge THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
ELSIF fault THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
ELSIF NOT local_hasPrev THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
ELSIF local_modeChanged THEN
    IF mode = 2 THEN
        flowSP := flowSP;
    ELSE
        flowSP := manualFlowSP;
    END_IF;
    valveCommand := valveCommand;
ELSE
    IF mode = 0 THEN
        flowSP := manualFlowSP;
        valveCommand := manualValve;
    ELSIF mode = 1 THEN
        flowSP := manualFlowSP;
        eF := flowSP - flowPV;
        raw := accF + 2.0 * eF + 0.5 * eF * scanSeconds;
        valveCommand := LIMIT(0.0, raw, 100.0);
    ELSIF mode = 2 THEN
        raw := accT + 1.0 * eT + 0.2 * eT * scanSeconds;
        flowSP := LIMIT(0.0, raw, 50.0);

        eF := flowSP - flowPV;
        raw := accF + 2.0 * eF + 0.5 * eF * scanSeconds;
        valveCommand := LIMIT(0.0, raw, 100.0);
    END_IF;
END_IF;

eF := flowSP - flowPV;
accT := flowSP - 1.0 * eT;
accF := valveCommand - 2.0 * eF;

normalMode := local_hasPrev AND (mode = local_prevMode) AND NOT fault AND NOT local_resetEdge;

local_prevMode := mode;
local_prevReset := resetBtn;
local_hasPrev := TRUE;

END_FUNCTION_BLOCK
FUNCTION_BLOCK FB
VAR_INPUT
    mode            : INT;
    resetBtn        : BOOL;
    scanSeconds     : REAL;
    tempSP          : REAL;
    tempPV          : REAL;
    flowPV          : REAL;
    manualFlowSP    : REAL;
    manualValve     : REAL;
END_VAR
VAR_OUTPUT
    flowSP          : REAL;
    valveCommand    : REAL;
    fault           : BOOL;
    normalMode      : BOOL;
END_VAR
VAR
    prevMode            : INT := -1;
    prevResetBtn        : BOOL := FALSE;
    prevNormalMode      : BOOL := FALSE;
    prevFlowSP          : REAL := 0.0;
    prevValveCommand    : REAL := 0.0;
    prevFlowSetpoint    : REAL := 0.0;
    accT                : REAL := 0.0;
    accF                : REAL := 0.0;
END_VAR
VAR_TEMP
    tmpRisingReset      : BOOL;
    tmpModeChanged      : BOOL;
    tmpTempError        : REAL;
    tmpFlowError        : REAL;
    tmpTrialFlow        : REAL;
    tmpTrialValve       : REAL;
END_VAR
(* ENGINEERING_CONTRACT
 * | Output/State     | Activation          | Retention/Hold         | Explicit Reset   | Same-Scan Priority | Units/Boundaries    |
 * |------------------|---------------------|------------------------|------------------|--------------------|---------------------|
 * | flowSP           | mode=2: cascaded PI | mode=2: hold prev; 0/1: hold prev | reset/fault: follow manualFlowSP | fault/reset > PI calc | 0..50 t/h, KpT=1.0, KiT=0.2/s |
 * | valveCommand     | mode>=1: cascaded PI| mode=1/2: hold prev; 0: follow manual | reset/fault: follow manualValve | fault/reset > PI calc | 0..100 %, KpF=2.0, KiF=0.5/s |
 * | fault            | mode∉{0,1,2} OR scanSeconds∉(0,10] | HOLD until mode/scanSeconds valid | resetBtn↑: cleared | evaluated before reset logic | Boolean |
 * | normalMode       | prevNormalMode AND stable OR stable_on_first; 2 consec stable scans reqd | mode change: FALSE until re-stabilized | resetBtn↑: FALSE | - | Boolean |
 * | accT (internal)  | mode=2 AND normalMode: back-calc from limited flowSP | mode≠2: retain | reset: 0.0 | PI calc > limit | t/h |
 * | accF (internal)  | mode≥1 AND normalMode: back-calc from limited valveCommand | mode<1: retain | reset: 0.0 | PI calc > limit | % |
 * PUB001: mode ∈ {0,1,2} required for normal; PUB002: scanSeconds ∈ (0,10] required
 * PUB003: resetBtn rising edge triggers re-initialization; PUB004:按住不放不重复动作
 * PUB005: mode switch bumpless: mode=2 holds both, mode=0/1 holds valve; PUB006: PI anti-windup by back-calculation
 * PUB007: first scan outputs initialized to manual values; PUB008: normalMode when stable non-fault non-reset
 *)

(* CONTRACT_RULES [] *)

tmpRisingReset := resetBtn AND NOT prevResetBtn;
tmpModeChanged := (mode <> prevMode);

fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

IF prevMode = -1 THEN
    normalMode := FALSE;
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    prevMode := mode;
    prevResetBtn := resetBtn;
    prevNormalMode := FALSE;
    prevFlowSP := manualFlowSP;
    prevValveCommand := manualValve;
    prevFlowSetpoint := manualFlowSP;
    RETURN;
END_IF;

IF tmpRisingReset THEN
    fault := FALSE;
    normalMode := FALSE;
    accT := 0.0;
    accF := 0.0;
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    prevResetBtn := TRUE;
    prevNormalMode := FALSE;
    prevFlowSP := manualFlowSP;
    prevValveCommand := manualValve;
    prevFlowSetpoint := manualFlowSP;
    prevMode := mode;
    RETURN;
END_IF;

IF tmpModeChanged AND NOT fault THEN
    normalMode := FALSE;
    IF mode = 2 THEN
        flowSP := prevFlowSP;
        valveCommand := prevValveCommand;
    ELSE
        flowSP := manualFlowSP;
        valveCommand := prevValveCommand;
    END_IF;
ELSE
    IF prevNormalMode AND (mode = prevMode) AND NOT fault AND NOT tmpRisingReset THEN
        normalMode := TRUE;
    ELSIF (NOT tmpModeChanged) AND (NOT prevNormalMode) AND NOT fault AND NOT tmpRisingReset THEN
        normalMode := TRUE;
    ELSE
        normalMode := FALSE;
    END_IF;
    
    IF normalMode THEN
        IF mode = 2 THEN
            tmpTempError := tempSP - tempPV;
            tmpTrialFlow := accT + 0.2 * tmpTempError * scanSeconds;
            flowSP := LIMIT(0.0, 1.0 * tmpTempError + tmpTrialFlow, 50.0);
            accT := flowSP - 1.0 * tmpTempError;
            
            tmpFlowError := flowSP - flowPV;
            tmpTrialValve := accF + 0.5 * tmpFlowError * scanSeconds;
            valveCommand := LIMIT(0.0, 2.0 * tmpFlowError + tmpTrialValve, 100.0);
            accF := valveCommand - 2.0 * tmpFlowError;
        ELSE
            flowSP := manualFlowSP;
            valveCommand := manualValve;
        END_IF;
    ELSE
        IF mode = 0 THEN
            flowSP := manualFlowSP;
            valveCommand := manualValve;
        ELSE
            flowSP := manualFlowSP;
            valveCommand := prevValveCommand;
        END_IF;
    END_IF;
END_IF;

prevMode := mode;
prevResetBtn := resetBtn;
prevNormalMode := normalMode;
prevFlowSP := flowSP;
prevValveCommand := valveCommand;
prevFlowSetpoint := flowSP;
END_FUNCTION_BLOCK
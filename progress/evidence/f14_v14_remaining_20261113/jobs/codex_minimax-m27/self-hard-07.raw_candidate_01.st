FUNCTION_BLOCK FB
VAR_INPUT
    mode                : INT;
    resetBtn            : BOOL;
    scanSeconds         : REAL;
    tempSP              : REAL;
    tempPV              : REAL;
    flowPV              : REAL;
    manualFlowSP        : REAL;
    manualValve         : REAL;
END_VAR
VAR_OUTPUT
    flowSP              : REAL;
    valveCommand        : REAL;
    fault               : BOOL;
    normalMode          : BOOL;
END_VAR
VAR
    accT                : REAL := 0.0;
    accF                : REAL := 0.0;
    mode_prev           : INT := 999;
    prev_resetBtn       : BOOL := FALSE;
    first_scan          : BOOL := TRUE;
END_VAR
VAR_TEMP
    eT                  : REAL;
    eF                  : REAL;
    trial               : REAL;
    reset_rising        : BOOL;
    mode_changed        : BOOL;
END_VAR
(* ENGINEERING_CONTRACT
 * =============================================================================
 * Modes: 0=Manual(FB), 1=Auto(inner PI), 2=Cascade(both PI loops)
 * Normal operation: mode in {0,1,2}, 0 < scanSeconds <= 10.0
 * Fault: mode outside {0,1,2} OR scanSeconds <= 0 OR scanSeconds > 10
 * -----------------------------------------------------------------------------
 * Output state retention (per LTL spec):
 * - Mode switch to 2 (cascade): flowSP, valveCommand HOLD prev; normalMode=FALSE
 * - Mode switch to 0/1: flowSP=manualFlowSP, valveCommand HOLD prev; normalMode=FALSE
 * - Manual (mode=0) normal cycle: flowSP=manualFlowSP, valveCommand=manualValve
 * - Auto (mode=1) normal cycle: flowSP=manualFlowSP; valveCommand=PI(clamped)
 * - Cascade (mode=2) normal cycle: flowSP=PI(clamped), valveCommand=PI(clamped)
 * - Fault: flowSP=manualFlowSP, valveCommand=manualValve, normalMode=FALSE
 * - Reset rising edge: same as fault initialization, fault still reports truthfully
 * -----------------------------------------------------------------------------
 * Integrators (anti-windup back-calculation):
 * - accT unit: t/h; accF unit: %; both pre-set to 0 on reset/fault/first scan
 * - acc update after output limit: acc = limited_output - Kp*e
 * - On mode change to cascade, both accT and accF retain prior cycle values
 * -----------------------------------------------------------------------------
 * Timing: Ki defined per second; scanSeconds multiplied explicitly
 * Boundaries: flowSP [0,50] t/h; valveCommand [0,100] %
 * =============================================================================
 *)
(* CONTRACT_RULES [] *)

reset_rising := resetBtn AND NOT prev_resetBtn;
mode_changed := (mode <> mode_prev);

fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

IF first_scan OR reset_rising THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    accT := 0.0;
    accF := 0.0;
    normalMode := FALSE;
    first_scan := FALSE;
ELSIF fault THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    accT := 0.0;
    accF := 0.0;
    normalMode := FALSE;
ELSE
    IF mode_changed THEN
        normalMode := FALSE;
        IF mode = 2 THEN
            // Cascade: hold both outputs
            // accT, accF retained for bumpless entry
        ELSIF (mode = 0) OR (mode = 1) THEN
            flowSP := manualFlowSP;
            // valveCommand held
        END_IF;
    ELSE
        normalMode := TRUE;
        IF mode = 2 THEN
            // Outer loop PI
            eT := tempSP - tempPV;
            accT := accT + 0.2 * eT * scanSeconds;
            trial := accT + 0.2 * eT * scanSeconds;
            flowSP := 1.0 * eT + trial;
            flowSP := LIMIT(0.0, flowSP, 50.0);
            accT := flowSP - 1.0 * eT;
            // Inner loop PI
            eF := flowSP - flowPV;
            accF := accF + 0.5 * eF * scanSeconds;
            trial := accF + 0.5 * eF * scanSeconds;
            valveCommand := 2.0 * eF + trial;
            valveCommand := LIMIT(0.0, valveCommand, 100.0);
            accF := valveCommand - 2.0 * eF;
        ELSIF mode = 1 THEN
            // Auto: flowSP from manual, inner PI
            flowSP := manualFlowSP;
            eF := flowSP - flowPV;
            accF := accF + 0.5 * eF * scanSeconds;
            trial := accF + 0.5 * eF * scanSeconds;
            valveCommand := 2.0 * eF + trial;
            valveCommand := LIMIT(0.0, valveCommand, 100.0);
            accF := valveCommand - 2.0 * eF;
        ELSIF mode = 0 THEN
            // Manual
            flowSP := manualFlowSP;
            valveCommand := manualValve;
        END_IF;
    END_IF;
END_IF;

mode_prev := mode;
prev_resetBtn := resetBtn;
END_FUNCTION_BLOCK
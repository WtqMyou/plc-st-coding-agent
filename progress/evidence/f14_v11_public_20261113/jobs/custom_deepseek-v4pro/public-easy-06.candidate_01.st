FUNCTION_BLOCK AerationBlowerDelayedStart
VAR_INPUT
    DO_LOW : BOOL;
    AERATION_E_STOP_NC : BOOL;
END_VAR
VAR_OUTPUT
    BLOWER_RUN : BOOL := FALSE;
    AERATION_BLOWER_CYCLE_COUNT : UINT := 0;
END_VAR
VAR
    local_startTimer : TON;
    local_runRise : R_TRIG;
END_VAR

(* ENGINEERING_CONTRACT
BLOWER_RUN:
  Activation: TON.Q becomes TRUE when DO_LOW AND AERATION_E_STOP_NC have remained TRUE for >= 5 s (PUB001).
  Retention/hold: remains TRUE while TON.Q stays TRUE with both input conditions TRUE (PUB001).
  Explicit reset/deactivation: immediately FALSE when DO_LOW is FALSE or emergency stop active (TON.IN := FALSE) (PUB002).
  Same-scan priority: disable/reset has priority over enable because TON.IN is evaluated first (PUB002).
  Units/boundaries: BOOL, unitless.

AERATION_BLOWER_CYCLE_COUNT:
  Activation/update: increments once on a FALSE-to-TRUE transition of BLOWER_RUN, detected by R_TRIG (PUB003).
  Retention/hold: retained between scans; no explicit reset specified (PUB003).
  Same-scan priority: updated after BLOWER_RUN is computed in the same scan (PUB003).
  Units/boundaries: UINT start count, initialized to 0; standard UINT wrap behavior at 65535 (PUB004).
*)

(* CONTRACT_RULES [] *)

local_startTimer(IN := DO_LOW AND AERATION_E_STOP_NC, PT := T#5S);
BLOWER_RUN := local_startTimer.Q;
local_runRise(CLK := BLOWER_RUN);
IF local_runRise.Q THEN
    AERATION_BLOWER_CYCLE_COUNT := AERATION_BLOWER_CYCLE_COUNT + UINT#1;
END_IF;

END_FUNCTION_BLOCK
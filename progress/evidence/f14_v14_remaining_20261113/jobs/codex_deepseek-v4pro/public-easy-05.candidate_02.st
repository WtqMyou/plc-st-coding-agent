FUNCTION_BLOCK WeldGapAlarm
VAR_INPUT
    Gap_Exceeded : BOOL;
    Weld_E_Stop_NC : BOOL;
    DebounceTime : TIME;
END_VAR
VAR_OUTPUT
    Operator_Alert : BOOL;
    Weld_Soft_Start_Active : BOOL;
END_VAR
VAR
    local_PowerUpTimer : TON;
    local_DebounceTimer : TON;
    local_DebounceEnable : BOOL;
END_VAR

(* CONTRACT_RULES [] *)

(* ENGINEERING_CONTRACT
Operator_Alert:
  Activate when E-stop inactive, power-up timer completed, and Gap_Exceeded has been TRUE continuously for DebounceTime.
  Hold while Gap_Exceeded remains TRUE after elapsed DebounceTime.
  Reset immediately on Gap_Exceeded=FALSE, E-stop active, or during initialization.
  Same-scan priority: E-stop active > initialization > debounced gap alarm.
Weld_Soft_Start_Active:
  Activate at power-up and hold TRUE for exactly the 5 s initialization period.
  Deactivate automatically when local_PowerUpTimer reaches 5 s; no manual reset.
  Same-scan priority: independent of E-stop and alarm deactivation.
Units/boundaries: power-up interval = T#5S; DebounceTime is TIME in milliseconds and must be positive.
*)

local_PowerUpTimer(IN := TRUE, PT := T#5S);

local_DebounceEnable := local_PowerUpTimer.Q
                        AND Weld_E_Stop_NC
                        AND Gap_Exceeded;

local_DebounceTimer(IN := local_DebounceEnable, PT := DebounceTime);

Weld_Soft_Start_Active := NOT local_PowerUpTimer.Q;
Operator_Alert := Weld_E_Stop_NC AND local_DebounceTimer.Q;

END_FUNCTION_BLOCK
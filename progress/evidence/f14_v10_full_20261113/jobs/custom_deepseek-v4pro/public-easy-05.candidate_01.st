FUNCTION_BLOCK WeldGapAlarm
VAR_INPUT
    Gap_Exceeded: BOOL;
    Weld_E_Stop_NC: BOOL;
    DebounceTime: TIME;
END_VAR
VAR_OUTPUT
    Operator_Alert: BOOL;
    Weld_Soft_Start_Active: BOOL;
END_VAR
VAR
    tmp_InitTimer: TON;
    tmp_DebounceTimer: TON;
    local_InitActive: BOOL;
    local_EStopActive: BOOL;
    local_DebounceEnable: BOOL;
END_VAR

(* ENGINEERING_CONTRACT
   Output/Group         Activation                                      Retention/Hold                     Explicit Reset/Deactivation       Same-scan priority        Units/Bounds                  PUB
   Operator_Alert       Gap_Exceeded TRUE for DebounceTime after init   Holds while eligible gap TRUE      Gap FALSE, E-stop FALSE, init   E-stop overrides monitor   TIME, positive assumed        PUB003 PUB004
   Weld_Soft_Start_Act  5 s power-up init timer not elapsed             TRUE during init unless E-stop    E-stop active, timer elapsed     E-stop overrides init       TIME 5 s                      PUB002 PUB004 PUB005
   Debounce timing      eligible gap TRUE in normal monitoring         accumulates only if eligible       Gap FALSE, E-stop, init         E-stop/init clear timing    DebounceTime TIME             PUB002 PUB003 PUB004
*)

(* CONTRACT_RULES [] *)

local_EStopActive := NOT Weld_E_Stop_NC;

tmp_InitTimer(IN := TRUE, PT := T#5S);
local_InitActive := NOT tmp_InitTimer.Q;

local_DebounceEnable := Gap_Exceeded AND NOT local_InitActive AND NOT local_EStopActive;
tmp_DebounceTimer(IN := local_DebounceEnable, PT := DebounceTime);

Operator_Alert := tmp_DebounceTimer.Q AND NOT local_EStopActive;
Weld_Soft_Start_Active := local_InitActive AND NOT local_EStopActive;

END_FUNCTION_BLOCK
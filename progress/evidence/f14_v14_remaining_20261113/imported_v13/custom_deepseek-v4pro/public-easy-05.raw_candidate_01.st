FUNCTION_BLOCK WeldGapAlarmControl
(* ENGINEERING_CONTRACT
Operator_Alert: combinational; active when Gap_Exceeded has been TRUE continuously for DebounceTime after init and no E-stop. No latch, not retained; deasserts when DeboundTimer.Q false or EStop active. PUB003/PUB004.
Weld_Soft_Start_Active: active while init timer NOT Q and EStop inactive. Deactivates on first scan where 5s init timer Q true. EStop masks; no latch. PUB002/PUB004/PUB005.
Init timer: TON always enabled from power-up; wall-clock 5s. EStop masks SoftStart but does not reset/pause init timer (unspecified).
Debounce timer: IN = Gap_Exceeded AND init done AND NOT EStopActive; resets on gap false, init, EStop. PT = DebounceTime (TIME ms). PUB002/PUB003/PUB004.
Same-scan priority: EStopActive computed first; init Q then debounce Q used same scan. Boundary: SoftStart off at first scan with InitTimer.Q true. PUB002/PUB003.
*)
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
    InitTimer : TON;
    DebounceTimer : TON;
    tmp_EStopActive : BOOL;
    tmp_InitDone : BOOL;
    tmp_DebounceEnable : BOOL;
END_VAR

(* CONTRACT_RULES [] *)

tmp_EStopActive := NOT Weld_E_Stop_NC;

InitTimer(IN := TRUE, PT := T#5S);
tmp_InitDone := InitTimer.Q;

tmp_DebounceEnable := Gap_Exceeded AND tmp_InitDone AND NOT tmp_EStopActive;
DebounceTimer(IN := tmp_DebounceEnable, PT := DebounceTime);

Operator_Alert := DebounceTimer.Q AND NOT tmp_EStopActive;
Weld_Soft_Start_Active := (NOT InitTimer.Q) AND (NOT tmp_EStopActive);

END_FUNCTION_BLOCK
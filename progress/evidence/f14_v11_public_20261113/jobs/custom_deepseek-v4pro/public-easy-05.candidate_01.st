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
    InitTimer : TON;
    DebounceTimer : TON;
END_VAR

(* ENGINEERING_CONTRACT
Operator_Alert:
  activation: InitTimer.Q AND Weld_E_Stop_NC AND DebounceTimer.Q (PUB003/PUB004)
  hold: remains TRUE only while activation condition is true each scan; no separate latch
  reset/deactivation: Gap_Exceeded FALSE, Weld_E_Stop_NC FALSE, or initialization active
  priority: E-Stop FALSE immediately clears debounce and output; initialization also forces FALSE
  units/boundary: BOOL; DebounceTime is TIME, alert only after Gap_Exceeded remains TRUE >= DebounceTime

Weld_Soft_Start_Active:
  activation: NOT InitTimer.Q, i.e. during first 5 s after power-up (PUB002/PUB005)
  hold: remains TRUE for the entire 5 s initialization window
  reset/deactivation: InitTimer.Q becomes TRUE at >= 5 s
  priority: E-Stop does not deassert this output; PUB004 omits it, so timer status is preserved
  units/boundary: BOOL; 5 s inclusive at timer Q edge

InitTimer:
  unconditional TON with PT := T#5S from first scan; Q is FALSE until ET >= 5 s, then TRUE
DebounceTimer:
  accumulates only when InitTimer.Q AND Weld_E_Stop_NC AND Gap_Exceeded
  reset: Gap_Exceeded FALSE, Weld_E_Stop_NC FALSE, or initialization active
  units: TIME; positive DebounceTime assumed per interface
*)

InitTimer(IN := TRUE, PT := T#5S);

DebounceTimer(
    IN := InitTimer.Q AND Weld_E_Stop_NC AND Gap_Exceeded,
    PT := DebounceTime
);

Weld_Soft_Start_Active := NOT InitTimer.Q;
Operator_Alert := Weld_E_Stop_NC AND DebounceTimer.Q;

(* CONTRACT_RULES [] *)

END_FUNCTION_BLOCK
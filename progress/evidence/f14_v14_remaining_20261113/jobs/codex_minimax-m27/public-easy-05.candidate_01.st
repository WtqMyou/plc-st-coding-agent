(* ENGINEERING_CONTRACT *)
(*
  Init period (5s post power-up):
    - PUB001: Operator_Alert=FALSE, Weld_Soft_Start_Active=TRUE, debounce suspended
  Normal monitoring (after init):
    - PUB002: Operator_Alert latches TRUE after Gap_Exceeded TRUE for DebounceTime
    - PUB002: Operator_Alert FALSE immediately when Gap_Exceeded FALSE (alarm clears)
  E-Stop priority:
    - PUB003: Operator_Alert=FALSE immediately, debounce cleared when Weld_E_Stop_NC=FALSE
  Weld_Soft_Start_Active:
    - PUB004: TRUE during init period only; FALSE during normal monitoring and E-Stop
  Timing:
    - PUB005: Init inhibition fixed at 5s (LTIME); DebounceTime must be positive
  Priority hierarchy:
    - PUB006: E-Stop (Weld_E_Stop_NC=FALSE) overrides init and monitoring unconditionally
*)

(* CONTRACT_RULES [{"kind":"hold_until_reset","output":"Operator_Alert","set_input":"Gap_Exceeded","reset_input":"Weld_E_Stop_NC"}] *)

FUNCTION_BLOCK Weld_Gap_Alarm
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
    init_timer : TON;
    debounce_timer : TON;
    tmp_init_done : BOOL;
END_VAR

// E-Stop priority: overrides init and monitoring
IF NOT Weld_E_Stop_NC THEN
    Operator_Alert := FALSE;
    Weld_Soft_Start_Active := FALSE;
    debounce_timer(IN := FALSE, PT := DebounceTime);
    init_timer(IN := FALSE, PT := T#5s);
    tmp_init_done := FALSE;
    RETURN;
END_IF;

// Initialization period (5 seconds)
init_timer(IN := NOT init_timer.Q, PT := T#5s);
Weld_Soft_Start_Active := NOT init_timer.Q;

IF NOT init_timer.Q THEN
    // During initialization: clear debounce
    debounce_timer(IN := FALSE, PT := DebounceTime);
    Operator_Alert := FALSE;
    RETURN;
END_IF;

// Normal monitoring after init complete
tmp_init_done := init_timer.Q;

debounce_timer(IN := Gap_Exceeded AND NOT Operator_Alert, PT := DebounceTime);

IF debounce_timer.Q THEN
    Operator_Alert := TRUE;
ELSIF NOT Gap_Exceeded THEN
    Operator_Alert := FALSE;
END_IF;

END_FUNCTION_BLOCK
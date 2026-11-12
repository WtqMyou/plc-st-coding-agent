FUNCTION_BLOCK WeldGapAlarm
VAR
    Gap_Exceeded          : BOOL;  (* Input: Scanner indication that gap exceeds 1.5 mm *)
    Weld_E_Stop_NC        : BOOL;  (* Input: TRUE = emergency stop inactive; FALSE = active *)
    DebounceTime          : TIME;  (* Input: gap-signal debounce duration during normal monitoring *)

    Operator_Alert        : BOOL;  (* Output: Audible and visual alarm command *)
    Weld_Soft_Start_Active: BOOL;  (* Output: Monitoring-inhibition status during power-up init *)

    TON_Init              : TON;   (* 5-second power-up initialization timer *)
    TON_Debounce          : TON;   (* Gap-signal debounce timer *)
    InitActive            : BOOL;  (* TRUE during the 5-second initialization period *)
    DebounceInput         : BOOL;  (* Internal enable for the debounce timer *)
END_VAR

(* Power-up initialization timer: always runs for the first 5 seconds *)
TON_Init(IN := TRUE, PT := T#5S);
InitActive := NOT TON_Init.Q;

(* Debounce input is enabled only during normal monitoring (after initialization) and when E-stop is inactive *)
DebounceInput := Gap_Exceeded AND NOT InitActive AND Weld_E_Stop_NC;
TON_Debounce(IN := DebounceInput, PT := DebounceTime);

(* Operator_Alert is active when debounce has elapsed, monitoring is active, and E-stop is inactive *)
Operator_Alert := TON_Debounce.Q AND NOT InitActive AND Weld_E_Stop_NC;

(* Weld_Soft_Start_Active indicates the power-up inhibition period, but only if E-stop is inactive *)
Weld_Soft_Start_Active := InitActive AND Weld_E_Stop_NC;

END_FUNCTION_BLOCK
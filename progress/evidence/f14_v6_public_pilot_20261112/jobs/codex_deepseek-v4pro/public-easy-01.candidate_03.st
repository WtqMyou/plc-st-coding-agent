(* ENGINEERING_CONTRACT
Output/Public State | Activation (PUB) | Retention/Hold | Reset/Deactivation (PUB) | Same-Scan Priority | Units/Boundaries
Pump_Motor          | bottleSensor (PUB003)         | latched after set through cycle | finishedButton (PUB008) | finishedButton reset wins; then set inputs latch | BOOL
Filling_Valve       | cleaningConfirmButton (PUB004) | latched after set through cycle | finishedButton (PUB008) | finishedButton reset wins; then set inputs latch | BOOL
Capping_Machine     | fillingConfirmButton (PUB005)  | latched after set through cycle | finishedButton (PUB008) | finishedButton reset wins; then set inputs latch | BOOL
Packing_Machine     | cappingConfirmButton (PUB006)  | latched after set through cycle | finishedButton (PUB008) | finishedButton reset wins; then set inputs latch | BOOL
Completion_Light    | packingConfirmButton (PUB007)  | latched after set until pickup | finishedButton (PUB008) | finishedButton reset wins; then set inputs latch | BOOL
All BOOL outputs; no step-enable interlock is applied beyond the specified triggers and finished reset.
*)

(* CONTRACT_RULES [
{"kind":"hold_until_reset","output":"Pump_Motor","set_input":"bottleSensor","reset_input":"finishedButton"},
{"kind":"hold_until_reset","output":"Filling_Valve","set_input":"cleaningConfirmButton","reset_input":"finishedButton"},
{"kind":"hold_until_reset","output":"Capping_Machine","set_input":"fillingConfirmButton","reset_input":"finishedButton"},
{"kind":"hold_until_reset","output":"Packing_Machine","set_input":"cappingConfirmButton","reset_input":"finishedButton"},
{"kind":"hold_until_reset","output":"Completion_Light","set_input":"packingConfirmButton","reset_input":"finishedButton"}
] *)

FUNCTION_BLOCK AutomatedFillingLine
VAR_INPUT
    bottleSensor : BOOL;
    cleaningConfirmButton : BOOL;
    fillingConfirmButton : BOOL;
    cappingConfirmButton : BOOL;
    packingConfirmButton : BOOL;
    finishedButton : BOOL;
END_VAR
VAR_OUTPUT
    Pump_Motor : BOOL;
    Filling_Valve : BOOL;
    Capping_Machine : BOOL;
    Packing_Machine : BOOL;
    Completion_Light : BOOL;
END_VAR

IF finishedButton THEN
    Pump_Motor := FALSE;
    Filling_Valve := FALSE;
    Capping_Machine := FALSE;
    Packing_Machine := FALSE;
    Completion_Light := FALSE;
ELSE
    IF bottleSensor THEN
        Pump_Motor := TRUE;
    END_IF;

    IF cleaningConfirmButton THEN
        Filling_Valve := TRUE;
    END_IF;

    IF fillingConfirmButton THEN
        Capping_Machine := TRUE;
    END_IF;

    IF cappingConfirmButton THEN
        Packing_Machine := TRUE;
    END_IF;

    IF packingConfirmButton THEN
        Completion_Light := TRUE;
    END_IF;
END_IF;

END_FUNCTION_BLOCK
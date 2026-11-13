(*
ENGINEERING_CONTRACT
Pump_Motor: set by bottleSensor; retained until finishedButton resets the cycle. BOOL output.
Filling_Valve: set by cleaningConfirmButton; retained until finishedButton resets the cycle. BOOL output.
Capping_Machine: set by fillingConfirmButton; retained until finishedButton resets the cycle. BOOL output.
Packing_Machine: set by cappingConfirmButton; retained until finishedButton resets the cycle. BOOL output.
Completion_Light: set by packingConfirmButton; reset by finishedButton (PUB006). BOOL output.
Later stage confirmations are not explicit stop events, so earlier outputs remain active. No numeric boundaries.
Same-scan: finishedButton reset takes priority over activation inputs.
*)

(* CONTRACT_RULES [{"kind":"hold_until_reset","output":"Pump_Motor","set_input":"bottleSensor","reset_input":"finishedButton"},{"kind":"hold_until_reset","output":"Filling_Valve","set_input":"cleaningConfirmButton","reset_input":"finishedButton"},{"kind":"hold_until_reset","output":"Capping_Machine","set_input":"fillingConfirmButton","reset_input":"finishedButton"},{"kind":"hold_until_reset","output":"Packing_Machine","set_input":"cappingConfirmButton","reset_input":"finishedButton"},{"kind":"hold_until_reset","output":"Completion_Light","set_input":"packingConfirmButton","reset_input":"finishedButton"}] *)

FUNCTION_BLOCK FillingLineControl
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
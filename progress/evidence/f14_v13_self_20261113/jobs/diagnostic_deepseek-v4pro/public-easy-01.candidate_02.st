(* ENGINEERING_CONTRACT
Independent retained outputs, all reset by finishedButton:
- Pump_Motor: set when bottleSensor TRUE, holds until finishedButton.
- Filling_Valve: set when cleaningConfirmButton TRUE, holds until finishedButton.
- Capping_Machine: set when fillingConfirmButton TRUE, holds until finishedButton.
- Packing_Machine: set when cappingConfirmButton TRUE and Capping_Machine active, holds until finishedButton.
- Completion_Light: set when packingConfirmButton TRUE and Packing_Machine active, reset by finishedButton.
Same-scan priority: finishedButton reset first, then trigger evaluations.
*)
(* CONTRACT_RULES [{"kind":"hold_until_reset","output":"Pump_Motor","set_input":"bottleSensor","reset_input":"finishedButton"},{"kind":"hold_until_reset","output":"Filling_Valve","set_input":"cleaningConfirmButton","reset_input":"finishedButton"},{"kind":"hold_until_reset","output":"Capping_Machine","set_input":"fillingConfirmButton","reset_input":"finishedButton"}] *)

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
VAR
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

    IF cappingConfirmButton AND Capping_Machine THEN
        Packing_Machine := TRUE;
    END_IF;

    IF packingConfirmButton AND Packing_Machine THEN
        Completion_Light := TRUE;
    END_IF;
END_IF;

END_FUNCTION_BLOCK

FUNCTION_BLOCK AutomatedFillingLineControl
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

(* ENGINEERING_CONTRACT
- Pump_Motor: activated by bottleSensor, retained/holds until finishedButton reset; PUB003.
- Filling_Valve: activated by cleaningConfirmButton, retained until finishedButton reset; PUB004.
- Capping_Machine: activated by fillingConfirmButton, retained until finishedButton reset; PUB005.
- Packing_Machine: activated by cappingConfirmButton, retained until finishedButton reset; PUB006.
- Completion_Light: activated by packingConfirmButton, retained until finishedButton reset; PUB007.
- finishedButton: explicit common reset for all outputs, applied last in same scan; PUB008.
- Outputs are BOOL; no time bounds. Activation inputs are level-latched, not edge-only.
*)

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

IF finishedButton THEN
    Pump_Motor := FALSE;
    Filling_Valve := FALSE;
    Capping_Machine := FALSE;
    Packing_Machine := FALSE;
    Completion_Light := FALSE;
END_IF;

END_FUNCTION_BLOCK
(* ENGINEERING_CONTRACT
Output/Public State | Activation (PUB) | Retention/Hold | Reset/Deactivation | Same-Scan Priority | Units/Boundaries
Pump_Motor | bottleSensor (PUB003) | latched after cycle start | finishedButton (PUB008) | finished reset wins | BOOL
Filling_Valve | cleaningConfirmButton AND Pump_Motor (PUB004) | latched after start | finishedButton (PUB008) | finished reset wins | BOOL
Capping_Machine | fillingConfirmButton AND Filling_Valve (PUB005) | latched after start | finishedButton (PUB008) | finished reset wins | BOOL
Packing_Machine | cappingConfirmButton AND Capping_Machine (PUB006) | latched after start | finishedButton (PUB008) | finished reset wins | BOOL
Completion_Light | packingConfirmButton AND Packing_Machine (PUB007) | latched until pickup | finishedButton (PUB008) | finished reset wins | BOOL
*)

(* CONTRACT_RULES [
 {"kind":"hold_until_reset","output":"Pump_Motor","set_input":"bottleSensor","reset_input":"finishedButton"}
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

    IF cleaningConfirmButton AND Pump_Motor THEN
        Filling_Valve := TRUE;
    END_IF;

    IF fillingConfirmButton AND Filling_Valve THEN
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
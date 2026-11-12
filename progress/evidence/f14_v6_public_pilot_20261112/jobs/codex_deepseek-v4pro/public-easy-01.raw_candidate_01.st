(* ENGINEERING_CONTRACT
Output/Public State | Activation (PUB) | Retention/Hold | Reset/Deactivation (PUB) | Same-Scan Priority | Units/Boundaries
Pump_Motor          | bottleSensor (PUB003) | holds through cleaning | cleaningConfirmButton (PUB004) | stage 0 sensor transition first | BOOL, stages 0..5
Filling_Valve       | cleaningConfirmButton (PUB004) | holds through filling | fillingConfirmButton (PUB005) | current stage only | BOOL
Capping_Machine     | fillingConfirmButton (PUB005) | holds through capping | cappingConfirmButton (PUB006) | current stage only | BOOL
Packing_Machine     | cappingConfirmButton (PUB006) | holds through packing | packingConfirmButton (PUB007) | current stage only | BOOL
Completion_Light    | packingConfirmButton (PUB007) | holds until pickup | finishedButton (PUB008) | stage 5 only | BOOL
Unspecified simultaneous assertions are serialized as one stage transition per scan.
*)
(* CONTRACT_RULES [] *)

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
VAR
    tmp_Stage : INT := 0;
END_VAR

CASE tmp_Stage OF
    0:
        IF bottleSensor THEN
            tmp_Stage := 1;
        END_IF;
    1:
        IF cleaningConfirmButton THEN
            tmp_Stage := 2;
        END_IF;
    2:
        IF fillingConfirmButton THEN
            tmp_Stage := 3;
        END_IF;
    3:
        IF cappingConfirmButton THEN
            tmp_Stage := 4;
        END_IF;
    4:
        IF packingConfirmButton THEN
            tmp_Stage := 5;
        END_IF;
    5:
        IF finishedButton THEN
            tmp_Stage := 0;
        END_IF;
END_CASE;

CASE tmp_Stage OF
    0:
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
    1:
        Pump_Motor := TRUE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
    2:
        Pump_Motor := FALSE;
        Filling_Valve := TRUE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
    3:
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := TRUE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
    4:
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := TRUE;
        Completion_Light := FALSE;
    5:
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := TRUE;
END_CASE;

END_FUNCTION_BLOCK
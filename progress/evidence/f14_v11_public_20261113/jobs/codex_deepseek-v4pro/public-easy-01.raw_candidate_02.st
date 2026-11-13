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
    stage : INT := 0;
END_VAR

(*
ENGINEERING_CONTRACT
Output           Activation / Retention / Explicit Deactivation / Same-Scan Priority
Pump_Motor:      activ=stage0 + bottleSensor (PUB001); hold=stage1; deact=cleaningConfirm -> stage2 (PUB004).
Filling_Valve:   activ=cleaningConfirm at stage1 (PUB004); hold=stage2; deact=fillingConfirm -> stage3 (PUB003).
Capping_Machine: activ=fillingConfirm at stage2 (PUB003); hold=stage3; deact=cappingConfirm -> stage4 (PUB004).
Packing_Machine: activ=cappingConfirm at stage3 (PUB004); hold=stage4; deact=packingConfirm -> stage5 (PUB005).
Completion_Light: activ=packingConfirm at stage4 (PUB005); hold=stage5; deact=finishedButton -> stage0 (PUB006).
All states retained in local stage; outputs mutually exclusive. Same scan: finished reset evaluated first, then one eligible sequence transition is applied.
*)

(* CONTRACT_RULES [] *)

IF finishedButton AND (stage = 5) THEN
    stage := 0;
END_IF;

IF (stage = 0) AND bottleSensor THEN
    stage := 1;
ELSIF (stage = 1) AND cleaningConfirmButton THEN
    stage := 2;
ELSIF (stage = 2) AND fillingConfirmButton THEN
    stage := 3;
ELSIF (stage = 3) AND cappingConfirmButton THEN
    stage := 4;
ELSIF (stage = 4) AND packingConfirmButton THEN
    stage := 5;
END_IF;

Pump_Motor := (stage = 1);
Filling_Valve := (stage = 2);
Capping_Machine := (stage = 3);
Packing_Machine := (stage = 4);
Completion_Light := (stage = 5);

END_FUNCTION_BLOCK
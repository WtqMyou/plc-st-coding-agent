FUNCTION_BLOCK AutomatedFillingLineControl
(* ENGINEERING_CONTRACT
Stage0 idle: all outputs OFF; bottleSensor activates Pump_Motor (PUB001).
Pump_Motor: holds until cleaningConfirm; off by cleaningConfirm (PUB002).
Filling_Valve: set by cleaningConfirm; holds until fillingConfirm; off by fillingConfirm (PUB003).
Capping_Machine: set by fillingConfirm; holds until cappingConfirm; off by cappingConfirm (PUB004).
Packing_Machine: set by cappingConfirm; holds until packingConfirm; off by packingConfirm (PUB005).
Completion_Light: set by packingConfirm; holds until finishedButton; off by finishedButton (PUB006).
Same-scan priority: process only current stage trigger; at most one stage advance per scan.
Units/boundaries: BOOL outputs, integer stage 0..5; no timer or delay used.
*)
(* CONTRACT_RULES [
{"kind":"hold_until_reset","output":"Pump_Motor","set_input":"bottleSensor","reset_input":"cleaningConfirmButton"},
{"kind":"hold_until_reset","output":"Filling_Valve","set_input":"cleaningConfirmButton","reset_input":"fillingConfirmButton"},
{"kind":"hold_until_reset","output":"Capping_Machine","set_input":"fillingConfirmButton","reset_input":"cappingConfirmButton"},
{"kind":"hold_until_reset","output":"Packing_Machine","set_input":"cappingConfirmButton","reset_input":"packingConfirmButton"},
{"kind":"hold_until_reset","output":"Completion_Light","set_input":"packingConfirmButton","reset_input":"finishedButton"}
] *)
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

IF tmp_Stage = 0 THEN
    IF bottleSensor THEN
        tmp_Stage := 1;
    END_IF;
ELSIF tmp_Stage = 1 THEN
    IF cleaningConfirmButton THEN
        tmp_Stage := 2;
    END_IF;
ELSIF tmp_Stage = 2 THEN
    IF fillingConfirmButton THEN
        tmp_Stage := 3;
    END_IF;
ELSIF tmp_Stage = 3 THEN
    IF cappingConfirmButton THEN
        tmp_Stage := 4;
    END_IF;
ELSIF tmp_Stage = 4 THEN
    IF packingConfirmButton THEN
        tmp_Stage := 5;
    END_IF;
ELSIF tmp_Stage = 5 THEN
    IF finishedButton THEN
        tmp_Stage := 0;
    END_IF;
END_IF;

Pump_Motor := (tmp_Stage = 1);
Filling_Valve := (tmp_Stage = 2);
Capping_Machine := (tmp_Stage = 3);
Packing_Machine := (tmp_Stage = 4);
Completion_Light := (tmp_Stage = 5);

END_FUNCTION_BLOCK
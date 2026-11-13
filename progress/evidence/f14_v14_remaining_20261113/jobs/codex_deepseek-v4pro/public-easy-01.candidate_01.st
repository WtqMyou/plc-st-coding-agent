(*
ENGINEERING_CONTRACT
Pump_Motor: set by bottleSensor in Idle (PUB001), hold in Cleaning, reset by cleaningConfirmButton -> Filling (PUB002), BOOL.
Filling_Valve: set by cleaningConfirmButton in Cleaning (PUB002), hold in Filling, reset by fillingConfirmButton -> Capping (PUB003), BOOL.
Capping_Machine: set by fillingConfirmButton in Filling (PUB003), hold in Capping, reset by cappingConfirmButton -> Packing (PUB004), BOOL.
Packing_Machine: set by cappingConfirmButton in Capping (PUB004), hold in Packing, reset by packingConfirmButton -> Completed (PUB005), BOOL.
Completion_Light: set by packingConfirmButton in Packing (PUB005), hold in Completed, reset by finishedButton -> Idle (PUB006), BOOL.
Same-scan: one state transition per scan from the current state; later inputs are processed on subsequent scans. No numeric boundaries.
*)

(* CONTRACT_RULES [{"kind":"hold_until_reset","output":"Pump_Motor","set_input":"bottleSensor","reset_input":"cleaningConfirmButton"},{"kind":"hold_until_reset","output":"Filling_Valve","set_input":"cleaningConfirmButton","reset_input":"fillingConfirmButton"},{"kind":"hold_until_reset","output":"Capping_Machine","set_input":"fillingConfirmButton","reset_input":"cappingConfirmButton"},{"kind":"hold_until_reset","output":"Packing_Machine","set_input":"cappingConfirmButton","reset_input":"packingConfirmButton"},{"kind":"hold_until_reset","output":"Completion_Light","set_input":"packingConfirmButton","reset_input":"finishedButton"}] *)

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
    State : INT := 0;
END_VAR

IF State = 0 AND bottleSensor THEN
    State := 1;
ELSIF State = 1 AND cleaningConfirmButton THEN
    State := 2;
ELSIF State = 2 AND fillingConfirmButton THEN
    State := 3;
ELSIF State = 3 AND cappingConfirmButton THEN
    State := 4;
ELSIF State = 4 AND packingConfirmButton THEN
    State := 5;
ELSIF State = 5 AND finishedButton THEN
    State := 0;
END_IF;

Pump_Motor := (State = 1);
Filling_Valve := (State = 2);
Capping_Machine := (State = 3);
Packing_Machine := (State = 4);
Completion_Light := (State = 5);

END_FUNCTION_BLOCK
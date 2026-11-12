(*
ENGINEERING_CONTRACT
- Pump_Motor: active in state Cleaning, set by bottleSensor true when idle, retained until cleaningConfirmButton true (PUB001-PUB003).
- Filling_Valve: active in state Filling, set by cleaningConfirmButton true in Cleaning, retained until fillingConfirmButton true (PUB003-PUB004).
- Capping_Machine: active in state Capping, set by fillingConfirmButton true in Filling, retained until cappingConfirmButton true (PUB004-PUB005).
- Packing_Machine: active in state Packing, set by cappingConfirmButton true in Capping, retained until packingConfirmButton true (PUB005-PUB006).
- Completion_Light: active in state Done, set by packingConfirmButton true in Packing, retained until finishedButton true (PUB006-PUB007).
- Same-scan priority: exactly one transition evaluated per scan via IF/ELSIF on current state; outputs updated after transition.
- Units/boundaries: all signals are BOOL; state is an integer constant 0..5; no timing or analog units involved.
*)
(* CONTRACT_RULES [] *)

FUNCTION_BLOCK AutomatedFillingLineControl
VAR CONSTANT
    ST_IDLE : INT := 0;
    ST_CLEANING : INT := 1;
    ST_FILLING : INT := 2;
    ST_CAPPING : INT := 3;
    ST_PACKING : INT := 4;
    ST_DONE : INT := 5;
END_VAR
VAR
    state : INT := 0; (* initial idle state *)
END_VAR

IF state = ST_IDLE THEN
    IF bottleSensor THEN
        state := ST_CLEANING;
    END_IF;
ELSIF state = ST_CLEANING THEN
    IF cleaningConfirmButton THEN
        state := ST_FILLING;
    END_IF;
ELSIF state = ST_FILLING THEN
    IF fillingConfirmButton THEN
        state := ST_CAPPING;
    END_IF;
ELSIF state = ST_CAPPING THEN
    IF cappingConfirmButton THEN
        state := ST_PACKING;
    END_IF;
ELSIF state = ST_PACKING THEN
    IF packingConfirmButton THEN
        state := ST_DONE;
    END_IF;
ELSIF state = ST_DONE THEN
    IF finishedButton THEN
        state := ST_IDLE;
    END_IF;
END_IF;

Pump_Motor := (state = ST_CLEANING);
Filling_Valve := (state = ST_FILLING);
Capping_Machine := (state = ST_CAPPING);
Packing_Machine := (state = ST_PACKING);
Completion_Light := (state = ST_DONE);

END_FUNCTION_BLOCK
(* ENGINEERING_CONTRACT
States: 0 Idle, 1 Cleaning, 2 Filling, 3 Capping, 4 Packing, 5 Complete.
Activation: bottleSensor rising edge in Idle -> Cleaning. Cleaning holds Pump_Motor until cleaningConfirmButton rising edge.
cleaningConfirmButton in Cleaning -> Filling. fillingConfirmButton in Filling -> Capping.
cappingConfirmButton in Capping -> Packing. packingConfirmButton in Packing -> Complete.
finishedButton in Complete -> Idle and resets all outputs.
Outputs active only in matching state: Pump_Motor/Cleaning, Filling_Valve/Filling,
Capping_Machine/Capping, Packing_Machine/Packing, Completion_Light/Complete.
Unspecified: simultaneous inputs in one scan resolve by current state only.
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
    state : INT := 0;
    tmp_nextState : INT := 0;

    tmp_lastBottle : BOOL := FALSE;
    tmp_lastCleaning : BOOL := FALSE;
    tmp_lastFilling : BOOL := FALSE;
    tmp_lastCapping : BOOL := FALSE;
    tmp_lastPacking : BOOL := FALSE;
    tmp_lastFinished : BOOL := FALSE;

    tmp_bottleRise : BOOL;
    tmp_cleaningRise : BOOL;
    tmp_fillingRise : BOOL;
    tmp_cappingRise : BOOL;
    tmp_packingRise : BOOL;
    tmp_finishedRise : BOOL;
END_VAR

(* Rising edge detection *)
tmp_bottleRise := bottleSensor AND NOT tmp_lastBottle;
tmp_lastBottle := bottleSensor;

tmp_cleaningRise := cleaningConfirmButton AND NOT tmp_lastCleaning;
tmp_lastCleaning := cleaningConfirmButton;

tmp_fillingRise := fillingConfirmButton AND NOT tmp_lastFilling;
tmp_lastFilling := fillingConfirmButton;

tmp_cappingRise := cappingConfirmButton AND NOT tmp_lastCapping;
tmp_lastCapping := cappingConfirmButton;

tmp_packingRise := packingConfirmButton AND NOT tmp_lastPacking;
tmp_lastPacking := packingConfirmButton;

tmp_finishedRise := finishedButton AND NOT tmp_lastFinished;
tmp_lastFinished := finishedButton;

(* Compute next state from current state and relevant rising edges *)
tmp_nextState := state;
CASE state OF
    0: (* Idle *)
        IF tmp_bottleRise THEN
            tmp_nextState := 1;
        END_IF;
    1: (* Cleaning *)
        IF tmp_cleaningRise THEN
            tmp_nextState := 2;
        END_IF;
    2: (* Filling *)
        IF tmp_fillingRise THEN
            tmp_nextState := 3;
        END_IF;
    3: (* Capping *)
        IF tmp_cappingRise THEN
            tmp_nextState := 4;
        END_IF;
    4: (* Packing *)
        IF tmp_packingRise THEN
            tmp_nextState := 5;
        END_IF;
    5: (* Complete *)
        IF tmp_finishedRise THEN
            tmp_nextState := 0;
        END_IF;
    ELSE
        tmp_nextState := 0;
END_CASE;
state := tmp_nextState;

(* Output assignment for current state *)
Pump_Motor := FALSE;
Filling_Valve := FALSE;
Capping_Machine := FALSE;
Packing_Machine := FALSE;
Completion_Light := FALSE;

CASE state OF
    1:
        Pump_Motor := TRUE;
    2:
        Filling_Valve := TRUE;
    3:
        Capping_Machine := TRUE;
    4:
        Packing_Machine := TRUE;
    5:
        Completion_Light := TRUE;
END_CASE;

END_FUNCTION_BLOCK
(* ENGINEERING_CONTRACT
States: 0 Idle, 1 Cleaning, 2 Filling, 3 Capping, 4 Packing, 5 Complete.
Activation: bottleSensor rising edge -> state=1 and Pump_Motor latch set.
Each subsequent confirmation button rising edge in the correct state advances state and sets the corresponding output latch:
- cleaningConfirmButton in state=1 -> state=2, Filling_Valve latch set.
- fillingConfirmButton in state=2 -> state=3, Capping_Machine latch set.
- cappingConfirmButton in state=3 -> state=4, Packing_Machine latch set.
- packingConfirmButton in state=4 -> state=5, Completion_Light latch set.
All output latches (including Pump_Motor) remain true until finishedButton rising edge resets them and state returns to 0.
Retention/hold: all outputs are held until finishedButton (PUB008).
Explicit reset: finishedButton rising edge clears all latches and state.
Same-scan priority: finishedButton reset has priority over any start triggers because reset is processed after transition logic? (We ensure reset occurs after all transitions in the scan, so if finishedButton and a confirm pressed same scan, state transition may occur but reset then clears latches; prioritizing reset.)
Units/boundaries: none.time; BOOL outputs only.
Unspecified: simultaneous multiple confirmations in one scan resolve by current state only; only the first relevant transition per scan is taken.
*)

(* CONTRACT_RULES [
  {"kind": "hold_until_reset", "output": "Pump_Motor", "set_input": "bottleSensor", "reset_input": "finishedButton"}
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
VAR
    state : INT := 0;
    pumpLatch : BOOL := FALSE;
    fillingValveLatch : BOOL := FALSE;
    cappingMachineLatch : BOOL := FALSE;
    packingMachineLatch : BOOL := FALSE;
    completionLightLatch : BOOL := FALSE;

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

(* Pump latch: set on bottle detection, reset on finished button *)
IF tmp_bottleRise THEN
    pumpLatch := TRUE;
END_IF;
IF tmp_finishedRise THEN
    pumpLatch := FALSE;
    fillingValveLatch := FALSE;
    cappingMachineLatch := FALSE;
    packingMachineLatch := FALSE;
    completionLightLatch := FALSE;
    state := 0; (* reset state as well *)
END_IF;

(* State transitions and output latch setting *)
CASE state OF
    0: (* Idle *)
        IF tmp_bottleRise THEN
            state := 1;
        END_IF;
    1: (* Cleaning *)
        IF tmp_cleaningRise THEN
            state := 2;
            fillingValveLatch := TRUE;
        END_IF;
    2: (* Filling *)
        IF tmp_fillingRise THEN
            state := 3;
            cappingMachineLatch := TRUE;
        END_IF;
    3: (* Capping *)
        IF tmp_cappingRise THEN
            state := 4;
            packingMachineLatch := TRUE;
        END_IF;
    4: (* Packing *)
        IF tmp_packingRise THEN
            state := 5;
            completionLightLatch := TRUE;
        END_IF;
    5: (* Complete *)
        (* finished button handled above; no other transitions *)
        ;
    ELSE
        state := 0;
END_CASE;

(* Output assignments from latches *)
Pump_Motor := pumpLatch;
Filling_Valve := fillingValveLatch;
Capping_Machine := cappingMachineLatch;
Packing_Machine := packingMachineLatch;
Completion_Light := completionLightLatch;

END_FUNCTION_BLOCK
(* ENGINEERING_CONTRACT
Outputs by state (state is persistent across scans):
- Pump_Motor: ON in CLEANING; starts when bottleSensor TRUE from IDLE; OFF on cleaningConfirmButton. Retained while CLEANING, even if bottleSensor falls (PUB001/PUB002).
- Filling_Valve: ON in FILLING; starts on cleaningConfirmButton in CLEANING; OFF on fillingConfirmButton (PUB002/PUB003).
- Capping_Machine: ON in CAPPING; starts on fillingConfirmButton in FILLING; OFF on cappingConfirmButton (PUB003/PUB004).
- Packing_Machine: ON in PACKING; starts on cappingConfirmButton in CAPPING; OFF on packingConfirmButton (PUB004/PUB005).
- Completion_Light: ON in COMPLETE; starts on packingConfirmButton in PACKING; reset by finishedButton (PUB005/PUB006/PUB007).
Same-scan priority:
- Primary ELSIF chain processes one normal step.
- If finishedButton resets to IDLE and bottleSensor is already TRUE, re-enter CLEANING immediately in same scan.
Outputs are assigned after transition logic using final state.
Buttons are treated as level-sensitive; pulse width/protocol unspecified.
*)
(* CONTRACT_RULES [
  {"kind":"hold_until_reset","output":"Pump_Motor","set_input":"bottleSensor","reset_input":"cleaningConfirmButton"},
  {"kind":"hold_until_reset","output":"Filling_Valve","set_input":"cleaningConfirmButton","reset_input":"fillingConfirmButton"},
  {"kind":"hold_until_reset","output":"Capping_Machine","set_input":"fillingConfirmButton","reset_input":"cappingConfirmButton"},
  {"kind":"hold_until_reset","output":"Packing_Machine","set_input":"cappingConfirmButton","reset_input":"packingConfirmButton"},
  {"kind":"hold_until_reset","output":"Completion_Light","set_input":"packingConfirmButton","reset_input":"finishedButton"}
] *)

FUNCTION_BLOCK FillingLineControl
VAR_INPUT
    bottleSensor: BOOL;
    cleaningConfirmButton: BOOL;
    fillingConfirmButton: BOOL;
    cappingConfirmButton: BOOL;
    packingConfirmButton: BOOL;
    finishedButton: BOOL;
END_VAR
VAR_OUTPUT
    Pump_Motor: BOOL;
    Filling_Valve: BOOL;
    Capping_Machine: BOOL;
    Packing_Machine: BOOL;
    Completion_Light: BOOL;
END_VAR
VAR
    step: INT := 0; (* 0=IDLE, 1=CLEANING, 2=FILLING, 3=CAPPING, 4=PACKING, 5=COMPLETE *)
END_VAR

(* Primary state transitions: at most one normal step per scan *)
IF step = 0 THEN
    IF bottleSensor THEN
        step := 1;
    END_IF;
ELSIF step = 1 THEN
    IF cleaningConfirmButton THEN
        step := 2;
    END_IF;
ELSIF step = 2 THEN
    IF fillingConfirmButton THEN
        step := 3;
    END_IF;
ELSIF step = 3 THEN
    IF cappingConfirmButton THEN
        step := 4;
    END_IF;
ELSIF step = 4 THEN
    IF packingConfirmButton THEN
        step := 5;
    END_IF;
ELSIF step = 5 THEN
    IF finishedButton THEN
        step := 0;
    END_IF;
END_IF;

(* Same-scan reactivation: if finished just reset state to IDLE and a bottle is
   already detected, start cleaning immediately instead of waiting one scan. *)
IF step = 0 THEN
    IF bottleSensor THEN
        step := 1;
    END_IF;
END_IF;

(* Output mapping based on final state *)
CASE step OF
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

    ELSE
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
END_CASE;

END_FUNCTION_BLOCK
(* ENGINEERING_CONTRACT
Outputs by state (state is persistent across scans):
- Pump_Motor: ON in CLEANING; starts when bottleSensor TRUE from IDLE; OFF on cleaningConfirmButton. Retained while CLEANING, even if bottleSensor falls (PUB001/PUB002).
- Filling_Valve: ON in FILLING; starts on cleaningConfirmButton in CLEANING; OFF on fillingConfirmButton (PUB002/PUB003).
- Capping_Machine: ON in CAPPING; starts on fillingConfirmButton in FILLING; OFF on cappingConfirmButton (PUB003/PUB004).
- Packing_Machine: ON in PACKING; starts on cappingConfirmButton in CAPPING; OFF on packingConfirmButton (PUB004/PUB005).
- Completion_Light: ON in COMPLETE; starts on packingConfirmButton in PACKING; reset by finishedButton (PUB005/PUB006/PUB007).
Same-scan priority: one state transition per call via ELSIF chain; outputs are assigned after transition using final state.
Buttons are treated as level-sensitive; pulse width/protocol unspecified.
*)
(* CONTRACT_RULES [] *)

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

(* State transitions: at most one per scan *)
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
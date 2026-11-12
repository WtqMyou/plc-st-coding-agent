FUNCTION_BLOCK AutomatedFillingLineControl
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

(* ENGINEERING_CONTRACT
- Pump_Motor: active from bottleSensor detection in Idle and latched through Cleaning; PUB003.
- Pump_Motor: deactivated when cleaningConfirmButton advances to Filling; PUB004.
- Filling_Valve: active from cleaningConfirmButton and held through Filling; PUB004.
- Filling_Valve: deactivated when fillingConfirmButton advances to Capping; PUB005.
- Capping_Machine: active from fillingConfirmButton and held through Capping; PUB005-PUB006.
- Capping_Machine: deactivated when cappingConfirmButton advances to Packing; PUB006.
- Packing_Machine: active from cappingConfirmButton and held through Packing; PUB006-PUB007.
- Packing_Machine: deactivated when packingConfirmButton lights Completion_Light; PUB007.
- Completion_Light: held until finishedButton resets it and returns to Idle; PUB007-PUB008.
- Level-checked inputs; only the current stage consumes its matching confirmation button.
- Same-scan priority: one stage transition per scan; output units are BOOL with no time bounds.
*)

CASE State OF
    0:
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;

        IF bottleSensor THEN
            Pump_Motor := TRUE;
            State := 1;
        END_IF;

    1:
        Pump_Motor := TRUE;

        IF cleaningConfirmButton THEN
            Pump_Motor := FALSE;
            Filling_Valve := TRUE;
            State := 2;
        END_IF;

    2:
        Filling_Valve := TRUE;

        IF fillingConfirmButton THEN
            Filling_Valve := FALSE;
            Capping_Machine := TRUE;
            State := 3;
        END_IF;

    3:
        Capping_Machine := TRUE;

        IF cappingConfirmButton THEN
            Capping_Machine := FALSE;
            Packing_Machine := TRUE;
            State := 4;
        END_IF;

    4:
        Packing_Machine := TRUE;

        IF packingConfirmButton THEN
            Packing_Machine := FALSE;
            Completion_Light := TRUE;
            State := 5;
        END_IF;

    5:
        Completion_Light := TRUE;

        IF finishedButton THEN
            Completion_Light := FALSE;
            State := 0;
        END_IF;
END_CASE;

END_FUNCTION_BLOCK
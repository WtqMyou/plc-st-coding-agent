FUNCTION_BLOCK FB
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
    cleaningConfirmEdge : BOOL;
    fillingConfirmEdge : BOOL;
    cappingConfirmEdge : BOOL;
    packingConfirmEdge : BOOL;
    finishedEdge : BOOL;
    prevCleaningConfirm : BOOL;
    prevFillingConfirm : BOOL;
    prevCappingConfirm : BOOL;
    prevPackingConfirm : BOOL;
    prevFinished : BOOL;
    CurrentStep : INT := 0;
    wasCleaning : BOOL;
END_VAR

cleaningConfirmEdge := cleaningConfirmButton AND NOT prevCleaningConfirm;
fillingConfirmEdge := fillingConfirmButton AND NOT prevFillingConfirm;
cappingConfirmEdge := cappingConfirmButton AND NOT prevCappingConfirm;
packingConfirmEdge := packingConfirmButton AND NOT prevPackingConfirm;
finishedEdge := finishedButton AND NOT prevFinished;

Pump_Motor := FALSE;
Filling_Valve := FALSE;
Capping_Machine := FALSE;
Packing_Machine := FALSE;
Completion_Light := FALSE;

IF finishedButton THEN
    IF finishedEdge THEN
        CurrentStep := 0;
    END_IF;
ELSE
    wasCleaning := (CurrentStep = 1);

    IF CurrentStep = 0 THEN
        IF bottleSensor THEN
            CurrentStep := 1;
        END_IF;
    ELSIF CurrentStep = 1 THEN
        IF cleaningConfirmEdge THEN
            CurrentStep := 2;
        END_IF;
    ELSIF CurrentStep = 2 THEN
        IF fillingConfirmEdge THEN
            CurrentStep := 3;
        END_IF;
    ELSIF CurrentStep = 3 THEN
        IF cappingConfirmEdge THEN
            CurrentStep := 4;
        END_IF;
    ELSIF CurrentStep = 4 THEN
        IF packingConfirmEdge THEN
            CurrentStep := 5;
        END_IF;
    END_IF;

    IF CurrentStep = 1 THEN
        Pump_Motor := TRUE;
    ELSIF CurrentStep = 2 THEN
        Filling_Valve := TRUE;
        IF cleaningConfirmEdge AND wasCleaning THEN
            Pump_Motor := TRUE;
        END_IF;
    ELSIF CurrentStep = 3 THEN
        Filling_Valve := TRUE;
        Capping_Machine := TRUE;
    ELSIF CurrentStep = 4 THEN
        Packing_Machine := TRUE;
    ELSIF CurrentStep = 5 THEN
        Packing_Machine := TRUE;
        Completion_Light := TRUE;
    END_IF;

    IF bottleSensor THEN
        Pump_Motor := TRUE;
    END_IF;
END_IF;

prevCleaningConfirm := cleaningConfirmButton;
prevFillingConfirm := fillingConfirmButton;
prevCappingConfirm := cappingConfirmButton;
prevPackingConfirm := packingConfirmButton;
prevFinished := finishedButton;

END_FUNCTION_BLOCK
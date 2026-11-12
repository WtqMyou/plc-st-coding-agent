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
    stepState : INT := 0;
    lastCleaningConfirmButton : BOOL := FALSE;
    lastFillingConfirmButton : BOOL := FALSE;
    lastCappingConfirmButton : BOOL := FALSE;
    lastPackingConfirmButton : BOOL := FALSE;
    lastFinishedButton : BOOL := FALSE;
    cleaningConfirmR : BOOL;
    fillingConfirmR : BOOL;
    cappingConfirmR : BOOL;
    packingConfirmR : BOOL;
    finishedR : BOOL;
END_VAR

cleaningConfirmR := cleaningConfirmButton AND NOT lastCleaningConfirmButton;
fillingConfirmR := fillingConfirmButton AND NOT lastFillingConfirmButton;
cappingConfirmR := cappingConfirmButton AND NOT lastCappingConfirmButton;
packingConfirmR := packingConfirmButton AND NOT lastPackingConfirmButton;
finishedR := finishedButton AND NOT lastFinishedButton;

CASE stepState OF
    0:
        IF bottleSensor THEN
            stepState := 1;
        END_IF;
    1:
        IF cleaningConfirmR THEN
            stepState := 2;
        END_IF;
    2:
        IF fillingConfirmR THEN
            stepState := 3;
        END_IF;
    3:
        IF cappingConfirmR THEN
            stepState := 4;
        END_IF;
    4:
        IF packingConfirmR THEN
            stepState := 5;
        END_IF;
    5:
        IF finishedR THEN
            stepState := 0;
        END_IF;
END_CASE;

Pump_Motor := (stepState = 1);
Filling_Valve := (stepState = 2);
Capping_Machine := (stepState = 3);
Packing_Machine := (stepState = 4);
Completion_Light := (stepState = 5);

lastCleaningConfirmButton := cleaningConfirmButton;
lastFillingConfirmButton := fillingConfirmButton;
lastCappingConfirmButton := cappingConfirmButton;
lastPackingConfirmButton := packingConfirmButton;
lastFinishedButton := finishedButton;

END_FUNCTION_BLOCK
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
    StepIndex : INT := 0;
END_VAR

IF StepIndex = 0 THEN
    Pump_Motor := FALSE;
    Filling_Valve := FALSE;
    Capping_Machine := FALSE;
    Packing_Machine := FALSE;
    Completion_Light := FALSE;
    IF bottleSensor THEN
        StepIndex := 1;
        Pump_Motor := TRUE;
    END_IF;
ELSIF StepIndex = 1 THEN
    Pump_Motor := TRUE;
    Filling_Valve := FALSE;
    Capping_Machine := FALSE;
    Packing_Machine := FALSE;
    Completion_Light := FALSE;
    IF cleaningConfirmButton THEN
        StepIndex := 2;
        Pump_Motor := FALSE;
        Filling_Valve := TRUE;
    END_IF;
ELSIF StepIndex = 2 THEN
    Pump_Motor := FALSE;
    Filling_Valve := TRUE;
    Capping_Machine := FALSE;
    Packing_Machine := FALSE;
    Completion_Light := FALSE;
    IF fillingConfirmButton THEN
        StepIndex := 3;
        Filling_Valve := FALSE;
        Capping_Machine := TRUE;
    END_IF;
ELSIF StepIndex = 3 THEN
    Pump_Motor := FALSE;
    Filling_Valve := FALSE;
    Capping_Machine := TRUE;
    Packing_Machine := FALSE;
    Completion_Light := FALSE;
    IF cappingConfirmButton THEN
        StepIndex := 4;
        Capping_Machine := FALSE;
        Packing_Machine := TRUE;
    END_IF;
ELSIF StepIndex = 4 THEN
    Pump_Motor := FALSE;
    Filling_Valve := FALSE;
    Capping_Machine := FALSE;
    Packing_Machine := TRUE;
    Completion_Light := FALSE;
    IF packingConfirmButton THEN
        StepIndex := 5;
        Packing_Machine := FALSE;
        Completion_Light := TRUE;
    END_IF;
ELSIF StepIndex = 5 THEN
    Pump_Motor := FALSE;
    Filling_Valve := FALSE;
    Capping_Machine := FALSE;
    Packing_Machine := FALSE;
    Completion_Light := TRUE;
    IF finishedButton THEN
        StepIndex := 0;
        Completion_Light := FALSE;
    END_IF;
END_IF;
END_FUNCTION_BLOCK
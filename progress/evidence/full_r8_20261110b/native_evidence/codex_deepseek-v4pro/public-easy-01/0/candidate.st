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
    prev_Pump_Motor : BOOL;
    prev_Filling_Valve : BOOL;
    prev_Capping_Machine : BOOL;
    prev_Packing_Machine : BOOL;
    prev_Completion_Light : BOOL;
END_VAR

IF finishedButton THEN
    Pump_Motor := FALSE;
    Filling_Valve := FALSE;
    Capping_Machine := FALSE;
    Packing_Machine := FALSE;
    Completion_Light := FALSE;
ELSE
    Pump_Motor := prev_Pump_Motor OR bottleSensor;
    Filling_Valve := prev_Filling_Valve OR (prev_Pump_Motor AND cleaningConfirmButton);
    Capping_Machine := prev_Capping_Machine OR (prev_Filling_Valve AND fillingConfirmButton);
    Packing_Machine := prev_Packing_Machine OR (prev_Capping_Machine AND cappingConfirmButton);
    Completion_Light := prev_Completion_Light OR (prev_Packing_Machine AND packingConfirmButton);
END_IF

prev_Pump_Motor := Pump_Motor;
prev_Filling_Valve := Filling_Valve;
prev_Capping_Machine := Capping_Machine;
prev_Packing_Machine := Packing_Machine;
prev_Completion_Light := Completion_Light;

END_FUNCTION_BLOCK
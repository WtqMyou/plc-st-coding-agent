FUNCTION_BLOCK FB
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
    prev_Pump: BOOL;
    prev_Filling: BOOL;
    prev_Capping: BOOL;
    prev_Packing: BOOL;
    prev_Completion: BOOL;
END_VAR

    prev_Pump := Pump_Motor;
    prev_Filling := Filling_Valve;
    prev_Capping := Capping_Machine;
    prev_Packing := Packing_Machine;
    prev_Completion := Completion_Light;

    IF finishedButton THEN
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
    ELSE
        Pump_Motor := bottleSensor OR prev_Pump;
        Filling_Valve := (prev_Pump AND cleaningConfirmButton) OR prev_Filling;
        Capping_Machine := (prev_Filling AND fillingConfirmButton) OR prev_Capping;
        Packing_Machine := (prev_Capping AND cappingConfirmButton) OR prev_Packing;
        Completion_Light := (prev_Packing AND packingConfirmButton) OR prev_Completion;
    END_IF

END_FUNCTION_BLOCK
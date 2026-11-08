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
    step: INT := 0;
END_VAR

IF finishedButton THEN
    step := 0;
    Pump_Motor := FALSE;
    Filling_Valve := FALSE;
    Capping_Machine := FALSE;
    Packing_Machine := FALSE;
    Completion_Light := FALSE;
ELSE
    CASE step OF
        0:
            IF bottleSensor THEN
                step := 1;
                Pump_Motor := TRUE;
                Filling_Valve := FALSE;
                Capping_Machine := FALSE;
                Packing_Machine := FALSE;
                Completion_Light := FALSE;
            ELSE
                Pump_Motor := FALSE;
                Filling_Valve := FALSE;
                Capping_Machine := FALSE;
                Packing_Machine := FALSE;
                Completion_Light := FALSE;
            END_IF

        1:
            Pump_Motor := TRUE;
            Filling_Valve := FALSE;
            Capping_Machine := FALSE;
            Packing_Machine := FALSE;
            Completion_Light := FALSE;
            IF cleaningConfirmButton THEN
                step := 2;
                Filling_Valve := TRUE;
            END_IF

        2:
            Pump_Motor := TRUE;
            Filling_Valve := TRUE;
            Capping_Machine := FALSE;
            Packing_Machine := FALSE;
            Completion_Light := FALSE;
            IF fillingConfirmButton THEN
                step := 3;
                Capping_Machine := TRUE;
            END_IF

        3:
            Pump_Motor := TRUE;
            Filling_Valve := TRUE;
            Capping_Machine := TRUE;
            Packing_Machine := FALSE;
            Completion_Light := FALSE;
            IF cappingConfirmButton THEN
                step := 4;
                Packing_Machine := TRUE;
            END_IF

        4:
            Pump_Motor := TRUE;
            Filling_Valve := TRUE;
            Capping_Machine := TRUE;
            Packing_Machine := TRUE;
            Completion_Light := FALSE;
            IF packingConfirmButton THEN
                step := 5;
                Completion_Light := TRUE;
            END_IF

        5:
            Pump_Motor := TRUE;
            Filling_Valve := TRUE;
            Capping_Machine := TRUE;
            Packing_Machine := TRUE;
            Completion_Light := TRUE;

    ELSE
        step := 0;
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
    END_CASE
END_IF

END_FUNCTION_BLOCK
FUNCTION_BLOCK FillingLineControl
VAR_INPUT
    bottleSensor           : BOOL;
    cleaningConfirmButton  : BOOL;
    fillingConfirmButton   : BOOL;
    cappingConfirmButton   : BOOL;
    packingConfirmButton   : BOOL;
    finishedButton         : BOOL;
END_VAR

VAR_OUTPUT
    Pump_Motor     : BOOL := FALSE;
    Filling_Valve  : BOOL := FALSE;
    Capping_Machine: BOOL := FALSE;
    Packing_Machine: BOOL := FALSE;
    Completion_Light: BOOL := FALSE;
END_VAR

VAR
    state : INT := 0;
    lastBottleSensor : BOOL := FALSE;
END_VAR

    // Detect bottle arrival
    IF bottleSensor AND NOT lastBottleSensor THEN
        state := 1;
    END_IF
    lastBottleSensor := bottleSensor;

    // State machine
    CASE state OF
        0:  // IDLE
            Pump_Motor := FALSE;
            Filling_Valve := FALSE;
            Capping_Machine := FALSE;
            Packing_Machine := FALSE;
            Completion_Light := FALSE;

        1:  // CLEANING
            Pump_Motor := TRUE;
            Filling_Valve := FALSE;
            Capping_Machine := FALSE;
            Packing_Machine := FALSE;
            Completion_Light := FALSE;
            IF cleaningConfirmButton THEN
                state := 2;
            END_IF

        2:  // FILLING
            Pump_Motor := FALSE;
            Filling_Valve := TRUE;
            Capping_Machine := FALSE;
            Packing_Machine := FALSE;
            Completion_Light := FALSE;
            IF fillingConfirmButton THEN
                state := 3;
            END_IF

        3:  // CAPPING
            Pump_Motor := FALSE;
            Filling_Valve := FALSE;
            Capping_Machine := TRUE;
            Packing_Machine := FALSE;
            Completion_Light := FALSE;
            IF cappingConfirmButton THEN
                state := 4;
            END_IF

        4:  // PACKING
            Pump_Motor := FALSE;
            Filling_Valve := FALSE;
            Capping_Machine := FALSE;
            Packing_Machine := TRUE;
            Completion_Light := FALSE;
            IF packingConfirmButton THEN
                state := 5;
            END_IF

        5:  // COMPLETE
            Pump_Motor := FALSE;
            Filling_Valve := FALSE;
            Capping_Machine := FALSE;
            Packing_Machine := FALSE;
            Completion_Light := TRUE;
            IF finishedButton THEN
                state := 0;
            END_IF
    END_CASE
END_FUNCTION_BLOCK
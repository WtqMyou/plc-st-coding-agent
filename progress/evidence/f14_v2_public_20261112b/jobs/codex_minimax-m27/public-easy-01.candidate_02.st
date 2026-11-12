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
    Pump_Motor      : BOOL := FALSE;
    Filling_Valve   : BOOL := FALSE;
    Capping_Machine : BOOL := FALSE;
    Packing_Machine : BOOL := FALSE;
    Completion_Light: BOOL := FALSE;
END_VAR

VAR
    state               : INT := 0;
    lastBottleSensor    : BOOL := FALSE;
    lastCleaningButton  : BOOL := FALSE;
    lastFillingButton   : BOOL := FALSE;
    lastCappingButton   : BOOL := FALSE;
    lastPackingButton   : BOOL := FALSE;
    lastFinishedButton  : BOOL := FALSE;
END_VAR

    // Detect bottle arrival on rising edge
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
            // Rising edge detection for button
            IF cleaningConfirmButton AND NOT lastCleaningButton THEN
                state := 2;
            END_IF

        2:  // FILLING
            Pump_Motor := FALSE;
            Filling_Valve := TRUE;
            Capping_Machine := FALSE;
            Packing_Machine := FALSE;
            Completion_Light := FALSE;
            // Rising edge detection for button
            IF fillingConfirmButton AND NOT lastFillingButton THEN
                state := 3;
            END_IF

        3:  // CAPPING
            Pump_Motor := FALSE;
            Filling_Valve := FALSE;
            Capping_Machine := TRUE;
            Packing_Machine := FALSE;
            Completion_Light := FALSE;
            // Rising edge detection for button
            IF cappingConfirmButton AND NOT lastCappingButton THEN
                state := 4;
            END_IF

        4:  // PACKING
            Pump_Motor := FALSE;
            Filling_Valve := FALSE;
            Capping_Machine := FALSE;
            Packing_Machine := TRUE;
            Completion_Light := FALSE;
            // Rising edge detection for button
            IF packingConfirmButton AND NOT lastPackingButton THEN
                state := 5;
            END_IF

        5:  // COMPLETE
            Pump_Motor := FALSE;
            Filling_Valve := FALSE;
            Capping_Machine := FALSE;
            Packing_Machine := FALSE;
            Completion_Light := TRUE;
            // Rising edge detection for button
            IF finishedButton AND NOT lastFinishedButton THEN
                state := 0;
            END_IF
    END_CASE

    // Update last button states for edge detection
    lastCleaningButton := cleaningConfirmButton;
    lastFillingButton := fillingConfirmButton;
    lastCappingButton := cappingConfirmButton;
    lastPackingButton := packingConfirmButton;
    lastFinishedButton := finishedButton;
END_FUNCTION_BLOCK
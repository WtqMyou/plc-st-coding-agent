FUNCTION_BLOCK FillingLineControl
VAR_INPUT
    bottleSensor         : BOOL;
    cleaningConfirmButton : BOOL;
    fillingConfirmButton  : BOOL;
    cappingConfirmButton  : BOOL;
    packingConfirmButton  : BOOL;
    finishedButton        : BOOL;
END_VAR

VAR_OUTPUT
    Pump_Motor      : BOOL;
    Filling_Valve   : BOOL;
    Capping_Machine : BOOL;
    Packing_Machine : BOOL;
    Completion_Light : BOOL;
END_VAR

VAR
    state : INT;
END_VAR

// State definitions:
// 0 = IDLE
// 1 = CLEANING
// 2 = FILLING
// 3 = CAPPING
// 4 = PACKAGING
// 5 = COMPLETED

// Reset all outputs at the start of each cycle
Pump_Motor      := FALSE;
Filling_Valve   := FALSE;
Capping_Machine := FALSE;
Packing_Machine := FALSE;
Completion_Light := FALSE;

CASE state OF
    0: // IDLE - Waiting for bottle
        IF bottleSensor THEN
            state := 1;
        END_IF;

    1: // CLEANING - Pump motor active
        Pump_Motor := TRUE;
        IF cleaningConfirmButton THEN
            state := 2;
        END_IF;

    2: // FILLING - Filling valve active
        Filling_Valve := TRUE;
        IF fillingConfirmButton THEN
            state := 3;
        END_IF;

    3: // CAPPING - Capping machine active
        Capping_Machine := TRUE;
        IF cappingConfirmButton THEN
            state := 4;
        END_IF;

    4: // PACKAGING - Packing machine active
        Packing_Machine := TRUE;
        IF packingConfirmButton THEN
            state := 5;
        END_IF;

    5: // COMPLETED - Completion light active
        Completion_Light := TRUE;
        IF finishedButton THEN
            state := 0;
        END_IF;

END_CASE;

END_FUNCTION_BLOCK
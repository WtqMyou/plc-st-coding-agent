FUNCTION_BLOCK FillingLineControl
VAR_INPUT
    bottleSensor          : BOOL;
    cleaningConfirmButton : BOOL;
    fillingConfirmButton  : BOOL;
    cappingConfirmButton  : BOOL;
    packingConfirmButton  : BOOL;
    finishedButton        : BOOL;
END_VAR

VAR_OUTPUT
    Pump_Motor       : BOOL;
    Filling_Valve    : BOOL;
    Capping_Machine  : BOOL;
    Packing_Machine  : BOOL;
    Completion_Light : BOOL;
END_VAR

VAR
    state : INT := 0;
END_VAR

// State: 0=IDLE, 1=CLEANING, 2=FILLING, 3=CAPPING, 4=PACKAGING, 5=COMPLETED

CASE state OF
    0: // IDLE
        IF bottleSensor THEN
            state := 1;
        END_IF;

    1: // CLEANING
        Pump_Motor := TRUE;
        IF cleaningConfirmButton THEN
            state := 2;
        END_IF;

    2: // FILLING
        Filling_Valve := TRUE;
        IF fillingConfirmButton THEN
            state := 3;
        END_IF;

    3: // CAPPING
        Capping_Machine := TRUE;
        IF cappingConfirmButton THEN
            state := 4;
        END_IF;

    4: // PACKAGING
        Packing_Machine := TRUE;
        IF packingConfirmButton THEN
            state := 5;
        END_IF;

    5: // COMPLETED
        Completion_Light := TRUE;
        IF finishedButton THEN
            state := 0;
        END_IF;

END_CASE;

END_FUNCTION_BLOCK
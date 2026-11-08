FUNCTION_BLOCK FB
VAR_INPUT
    bottleSensor           : BOOL;
    cleaningConfirmButton  : BOOL;
    fillingConfirmButton   : BOOL;
    cappingConfirmButton   : BOOL;
    packingConfirmButton   : BOOL;
    finishedButton         : BOOL;
END_VAR

VAR_OUTPUT
    Pump_Motor        : BOOL;
    Filling_Valve     : BOOL;
    Capping_Machine   : BOOL;
    Packing_Machine   : BOOL;
    Completion_Light  : BOOL;
END_VAR

VAR
    step                  : INT := 0;
    prevBottleSensor      : BOOL := FALSE;
    prevCleaningConfirm   : BOOL := FALSE;
    prevFillingConfirm    : BOOL := FALSE;
    prevCappingConfirm    : BOOL := FALSE;
    prevPackingConfirm    : BOOL := FALSE;
    prevFinishedButton    : BOOL := FALSE;
END_VAR

// Rising edge detection
VAR
    bottleRising         : BOOL;
    cleaningRising       : BOOL;
    fillingRising        : BOOL;
    cappingRising        : BOOL;
    packingRising        : BOOL;
    finishedRising       : BOOL;
END_VAR

bottleRising       := bottleSensor        AND NOT prevBottleSensor;
cleaningRising     := cleaningConfirmButton  AND NOT prevCleaningConfirm;
fillingRising      := fillingConfirmButton   AND NOT prevFillingConfirm;
cappingRising      := cappingConfirmButton   AND NOT prevCappingConfirm;
packingRising      := packingConfirmButton   AND NOT prevPackingConfirm;
finishedRising     := finishedButton      AND NOT prevFinishedButton;

// State machine transitions
IF step = 0 THEN
    IF bottleRising THEN
        step := 1;
    END_IF
ELSIF step = 1 THEN
    IF cleaningRising THEN
        step := 2;
    END_IF
ELSIF step = 2 THEN
    IF fillingRising THEN
        step := 3;
    END_IF
ELSIF step = 3 THEN
    IF cappingRising THEN
        step := 4;
    END_IF
ELSIF step = 4 THEN
    IF packingRising THEN
        step := 5;
    END_IF
END_IF

// Output logic based on step
Pump_Motor       := (step >= 1);
Filling_Valve    := (step >= 2);
Capping_Machine  := (step >= 3);
Packing_Machine  := (step >= 4);
Completion_Light := (step >= 5);

// Reset on finishedButton rising only when in COMPLETE state
IF finishedRising AND (step = 5) THEN
    step := 0;
END_IF

// Update previous states
prevBottleSensor    := bottleSensor;
prevCleaningConfirm := cleaningConfirmButton;
prevFillingConfirm  := fillingConfirmButton;
prevCappingConfirm  := cappingConfirmButton;
prevPackingConfirm  := packingConfirmButton;
prevFinishedButton  := finishedButton;
END_FUNCTION_BLOCK
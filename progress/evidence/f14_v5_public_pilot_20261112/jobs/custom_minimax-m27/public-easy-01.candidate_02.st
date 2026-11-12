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
    eState    : INT;
    nextState : INT;
END_VAR

// ENGINEERING_CONTRACT
// States: 0=IDLE, 1=CLEANING, 2=FILLING, 3=CAPPING, 4=PACKING, 5=COMPLETED
// PUB003: bottleSensor triggers pump motor continuously (retriggers if bottle stays)
// PUB004-PUB007: Each confirm button advances to next stage; next output activates immediately
// PUB008: finishedButton resets to IDLE; all outputs deactivate, Completion_Light clears
// Output retention: No output holds state beyond its stage; Completion_Light is latched until reset
// Same-scan priority: Two-CASE pattern prevents premature output assignment during transition evaluation
// Boundaries: bottleSensor edge-sensitive to detected; confirm buttons level-triggered per stage

nextState := eState;
CASE eState OF
    0:
        IF bottleSensor THEN
            nextState := 1;
        END_IF;
    1:
        IF cleaningConfirmButton THEN
            nextState := 2;
        END_IF;
    2:
        IF fillingConfirmButton THEN
            nextState := 3;
        END_IF;
    3:
        IF cappingConfirmButton THEN
            nextState := 4;
        END_IF;
    4:
        IF packingConfirmButton THEN
            nextState := 5;
        END_IF;
    5:
        IF finishedButton THEN
            nextState := 0;
        END_IF;
END_CASE;

eState := nextState;

CASE eState OF
    0:
        Pump_Motor       := FALSE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        Completion_Light := FALSE;
    1:
        Pump_Motor       := TRUE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        Completion_Light := FALSE;
    2:
        Pump_Motor       := FALSE;
        Filling_Valve    := TRUE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        Completion_Light := FALSE;
    3:
        Pump_Motor       := FALSE;
        Filling_Valve    := FALSE;
        Capping_Machine  := TRUE;
        Packing_Machine  := FALSE;
        Completion_Light := FALSE;
    4:
        Pump_Motor       := FALSE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := TRUE;
        Completion_Light := FALSE;
    5:
        Pump_Motor       := FALSE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        Completion_Light := TRUE;
END_CASE;

END_FUNCTION_BLOCK
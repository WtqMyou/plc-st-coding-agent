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
    eState : INT;
END_VAR

// ENGINEERING_CONTRACT
// States: 0=IDLE, 1=CLEANING, 2=FILLING, 3=CAPPING, 4=PACKING, 5=COMPLETED
// PUB003: bottleSensor triggers pump motor continuously (retriggers if bottle stays)
// PUB004-PUB007: Each confirm button advances to next stage; next output activates immediately
// PUB008: finishedButton resets to IDLE; all outputs deactivate, Completion_Light clears
// Output retention: No output holds state beyond its stage; Completion_Light is latched until reset
// Same-scan priority: Transition logic evaluated after output assignments per state
// Boundaries: bottleSensor edge-sensitive to detected; confirm buttons level-triggered per stage

CASE eState OF
    0: // IDLE
        Pump_Motor       := FALSE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        Completion_Light := FALSE;
        IF bottleSensor THEN
            eState := 1;
        END_IF;

    1: // CLEANING
        Pump_Motor       := TRUE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        Completion_Light := FALSE;
        IF cleaningConfirmButton THEN
            eState := 2;
        END_IF;

    2: // FILLING
        Pump_Motor       := FALSE;
        Filling_Valve    := TRUE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        Completion_Light := FALSE;
        IF fillingConfirmButton THEN
            eState := 3;
        END_IF;

    3: // CAPPING
        Pump_Motor       := FALSE;
        Filling_Valve    := FALSE;
        Capping_Machine  := TRUE;
        Packing_Machine  := FALSE;
        Completion_Light := FALSE;
        IF cappingConfirmButton THEN
            eState := 4;
        END_IF;

    4: // PACKING
        Pump_Motor       := FALSE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := TRUE;
        Completion_Light := FALSE;
        IF packingConfirmButton THEN
            eState := 5;
        END_IF;

    5: // COMPLETED
        Pump_Motor       := FALSE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        Completion_Light := TRUE;
        IF finishedButton THEN
            eState := 0;
        END_IF;

END_CASE;

END_FUNCTION_BLOCK
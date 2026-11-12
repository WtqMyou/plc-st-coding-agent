(*
ENGINEERING_CONTRACT
================================================================================
State Machine: Automated Filling Line (5-stage sequential + reset)
Clause ID | Output/State    | Activation          | Retention       | Reset
----------|-----------------|---------------------|-----------------|------------------
PUB003    | Pump_Motor      | bottleSensor=1      | Hold in CLEANING| cleaningConfirmButton (→FILLING)
PUB004    | Filling_Valve   | cleaningConfirmBtn  | Hold in FILLING | fillingConfirmButton (→CAPPING)
PUB005    | Capping_Machine | fillingConfirmBtn   | Hold in CAPPING | cappingConfirmButton (→PACKING)
PUB006    | Packing_Machine | cappingConfirmBtn   | Hold in PACKING | packingConfirmButton (→COMPLETE)
PUB007    | Completion_Light| packingConfirmBtn   | Hold until RESET| finishedButton (→IDLE)
PUB008    | (finishedButton)| Reset all, cycle end| N/A             | Automatic →IDLE
--------------------------------------------------------------------------------
Priority: Same-scan sequential (IDLE→CLEANING→FILLING→CAPPING→PACKING→COMPLETE→IDLE)
Units: None (binary signals, no timeouts specified)
Boundary: bottleSensor rising edge starts CLEANING; finishedButton resets COMPLETE→IDLE
--------------------------------------------------------------------------------
CONTRACT_RULES []
================================================================================
*)

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
    Pump_Motor      : BOOL;
    Filling_Valve   : BOOL;
    Capping_Machine : BOOL;
    Packing_Machine : BOOL;
    Completion_Light: BOOL;
END_VAR
VAR
    eState : INT;
END_VAR

// State enumeration: 0=IDLE, 1=CLEANING, 2=FILLING, 3=CAPPING, 4=PACKING, 5=COMPLETE
CASE eState OF
    0: // IDLE
        Pump_Motor       := FALSE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        Completion_Light := FALSE;
        IF bottleSensor THEN
            eState := 1; // → CLEANING
        END_IF;

    1: // CLEANING
        Pump_Motor       := TRUE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        Completion_Light := FALSE;
        IF cleaningConfirmButton THEN
            eState := 2; // → FILLING
        END_IF;

    2: // FILLING
        Pump_Motor       := FALSE;
        Filling_Valve    := TRUE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        Completion_Light := FALSE;
        IF fillingConfirmButton THEN
            eState := 3; // → CAPPING
        END_IF;

    3: // CAPPING
        Pump_Motor       := FALSE;
        Filling_Valve    := FALSE;
        Capping_Machine  := TRUE;
        Packing_Machine  := FALSE;
        Completion_Light := FALSE;
        IF cappingConfirmButton THEN
            eState := 4; // → PACKING
        END_IF;

    4: // PACKING
        Pump_Motor       := FALSE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := TRUE;
        Completion_Light := FALSE;
        IF packingConfirmButton THEN
            eState := 5; // → COMPLETE
        END_IF;

    5: // COMPLETE
        Pump_Motor       := FALSE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        Completion_Light := TRUE;
        IF finishedButton THEN
            eState := 0; // → IDLE (cycle reset)
        END_IF;

END_CASE;

END_FUNCTION_BLOCK
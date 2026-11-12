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

// State: 0=IDLE, 1=CLEANING, 2=FILLING, 3=CAPPING, 4=PACKING, 5=COMPLETE
// Reset all outputs each scan to ensure clean state transitions
Pump_Motor      := FALSE;
Filling_Valve   := FALSE;
Capping_Machine := FALSE;
Packing_Machine := FALSE;
Completion_Light:= FALSE;

// State transitions - sequential same-scan processing
IF eState = 0 AND bottleSensor THEN
    eState := 1;
END_IF;

IF eState = 1 AND cleaningConfirmButton THEN
    eState := 2;
END_IF;

IF eState = 2 AND fillingConfirmButton THEN
    eState := 3;
END_IF;

IF eState = 3 AND cappingConfirmButton THEN
    eState := 4;
END_IF;

IF eState = 4 AND packingConfirmButton THEN
    eState := 5;
END_IF;

IF eState = 5 AND finishedButton THEN
    eState := 0;
END_IF;

// Output activation based on current state
IF eState = 1 THEN
    Pump_Motor := TRUE;
END_IF;

IF eState = 2 THEN
    Filling_Valve := TRUE;
END_IF;

IF eState = 3 THEN
    Capping_Machine := TRUE;
END_IF;

IF eState = 4 THEN
    Packing_Machine := TRUE;
END_IF;

IF eState = 5 THEN
    Completion_Light := TRUE;
END_IF;

END_FUNCTION_BLOCK
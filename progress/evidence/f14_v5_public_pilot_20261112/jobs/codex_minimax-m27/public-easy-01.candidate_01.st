(*
ENGINEERING_CONTRACT - Filling Line Control FB
==============================================
State Machine: Sequential, 6 states (IDLE→CLEANING→FILLING→CAPPING→PACKING→COMPLETED→IDLE)
---------------------------------------------------------------------------------
| State       | Activation         | Retention              | Reset/Deactivation            |
---------------------------------------------------------------------------------
| IDLE        | bottleSensor=TRUE  | Hold until bottle      | Deact on bottleSensor:=TRUE   |
| CLEANING    | cleaningConfirm    | Pump_Motor ON hold     | Deact on cleaningConfirm      |
| FILLING     | fillingConfirm     | Filling_Valve ON hold  | Deact on fillingConfirm       |
| CAPPING     | cappingConfirm     | Capping_Machine ON hold| Deact on cappingConfirm       |
| PACKING     | packingConfirm     | Packing_Machine ON hold| Deact on packingConfirm       |
| COMPLETED   | packingConfirm     | Completion_Light ON    | Deact on finishedButton       |
---------------------------------------------------------------------------------
Priority: IDLE > COMPLETED > CLEANING > FILLING > CAPPING > PACKING (same-scan)
Units: All inputs/outputs BOOL; all states enumerated; no TIME/LTIME used
Boundaries: bottleSensor triggers only from IDLE; finishedButton resets only from COMPLETED
PUB refs: PUB001, PUB003, PUB004, PUB005, PUB006, PUB007, PUB008
---------------------------------------------------------------------------------
*)
FUNCTION_BLOCK FillingLineControl
VAR
    eState : EFillState := EFillState.IDLE;
END_VAR

TYPE EFillState :
(
    IDLE       := 0,
    CLEANING   := 1,
    FILLING    := 2,
    CAPPING    := 3,
    PACKING    := 4,
    COMPLETED  := 5
);
END_TYPE;

CASE eState OF
    EFillState.IDLE:
        Pump_Motor       := FALSE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        Completion_Light := FALSE;
        
        IF bottleSensor THEN
            eState := EFillState.CLEANING;
        END_IF;

    EFillState.CLEANING:
        Pump_Motor       := TRUE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        Completion_Light := FALSE;
        
        IF cleaningConfirmButton THEN
            eState := EFillState.FILLING;
        END_IF;

    EFillState.FILLING:
        Pump_Motor       := TRUE;
        Filling_Valve    := TRUE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        Completion_Light := FALSE;
        
        IF fillingConfirmButton THEN
            eState := EFillState.CAPPING;
        END_IF;

    EFillState.CAPPING:
        Pump_Motor       := TRUE;
        Filling_Valve    := FALSE;
        Capping_Machine  := TRUE;
        Packing_Machine  := FALSE;
        Completion_Light := FALSE;
        
        IF cappingConfirmButton THEN
            eState := EFillState.PACKING;
        END_IF;

    EFillState.PACKING:
        Pump_Motor       := TRUE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := TRUE;
        Completion_Light := FALSE;
        
        IF packingConfirmButton THEN
            eState := EFillState.COMPLETED;
        END_IF;

    EFillState.COMPLETED:
        Pump_Motor       := TRUE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        Completion_Light := TRUE;
        
        IF finishedButton THEN
            eState := EFillState.IDLE;
        END_IF;

END_CASE;

END_FUNCTION_BLOCK
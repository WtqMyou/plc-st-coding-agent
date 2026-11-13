(* ENGINEERING_CONTRACT
 * Filling Line State Machine - 6 states, sequential operation
 * PUB001: bottleSensor TRUE → Pump_Motor := TRUE (hold until cleaningConfirmButton)
 * PUB002: cleaningConfirmButton → Filling_Valve := TRUE (hold until fillingConfirmButton)
 * PUB003: fillingConfirmButton → Capping_Machine := TRUE (hold until cappingConfirmButton)
 * PUB004: cappingConfirmButton → Packing_Machine := TRUE (hold until packingConfirmButton)
 * PUB005: packingConfirmButton → Completion_Light := TRUE (hold until finishedButton)
 * PUB006: finishedButton → Completion_Light := FALSE; all outputs FALSE; reset to IDLE
 * State retention: outputs held until explicitly deactivated by state transition or reset
 * Reset priority: finishedButton (PUB006) clears all outputs and returns to IDLE
 *)

(* CONTRACT_RULES [] *)

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
    State : INT := 0;
END_VAR

// State machine: 0=IDLE, 1=CLEANING, 2=FILLING, 3=CAPPING, 4=PACKING, 5=COMPLETE
CASE State OF
    0: // IDLE - waiting for bottle
        Pump_Motor      := FALSE;
        Filling_Valve   := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light:= FALSE;
        
        IF bottleSensor THEN
            State := 1;
        END_IF
        
    1: // CLEANING
        Pump_Motor := TRUE;
        
        IF cleaningConfirmButton THEN
            Pump_Motor := FALSE;
            State := 2;
        END_IF
        
    2: // FILLING
        Filling_Valve := TRUE;
        
        IF fillingConfirmButton THEN
            Filling_Valve := FALSE;
            State := 3;
        END_IF
        
    3: // CAPPING
        Capping_Machine := TRUE;
        
        IF cappingConfirmButton THEN
            Capping_Machine := FALSE;
            State := 4;
        END_IF
        
    4: // PACKING
        Packing_Machine := TRUE;
        
        IF packingConfirmButton THEN
            Packing_Machine := FALSE;
            State := 5;
        END_IF
        
    5: // COMPLETE - bottle ready for pickup
        Completion_Light := TRUE;
        
        IF finishedButton THEN
            Completion_Light := FALSE;
            State := 0;
        END_IF
        
END_CASE

END_FUNCTION_BLOCK
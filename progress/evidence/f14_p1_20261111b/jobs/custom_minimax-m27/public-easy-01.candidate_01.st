PROGRAM AutomatedFillingLine
VAR
    (* Input variables *)
    bottleSensor           BOOL;
    cleaningConfirmButton  BOOL;
    fillingConfirmButton   BOOL;
    cappingConfirmButton   BOOL;
    packingConfirmButton   BOOL;
    finishedButton         BOOL;
    
    (* Output variables *)
    Pump_Motor             BOOL;
    Filling_Valve          BOOL;
    Capping_Machine        BOOL;
    Packing_Machine        BOOL;
    Completion_Light       BOOL;
    
    (* Internal state variable *)
    CurrentState           INT;
END_VAR

(* State definitions *)
CONST
    STATE_IDLE      := 0;
    STATE_CLEANING  := 1;
    STATE_FILLING   := 2;
    STATE_CAPPING   := 3;
    STATE_PACKING   := 4;
    STATE_COMPLETED := 5;
END_CONST

(* Initialize all outputs to FALSE *)
Pump_Motor       := FALSE;
Filling_Valve    := FALSE;
Capping_Machine  := FALSE;
Packing_Machine  := FALSE;
Completion_Light := FALSE;

(* State machine logic *)
CASE CurrentState OF

    STATE_IDLE:
        (* Reset all outputs *)
        Pump_Motor       := FALSE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        Completion_Light := FALSE;
        
        (* Transition to CLEANING when bottle is detected *)
        IF bottleSensor THEN
            CurrentState := STATE_CLEANING;
        END_IF

    STATE_CLEANING:
        (* Activate cleaning pump *)
        Pump_Motor := TRUE;
        
        (* Transition to FILLING when cleaning is confirmed *)
        IF cleaningConfirmButton THEN
            CurrentState := STATE_FILLING;
        END_IF

    STATE_FILLING:
        (* Activate filling valve *)
        Filling_Valve := TRUE;
        
        (* Transition to CAPPING when filling is confirmed *)
        IF fillingConfirmButton THEN
            CurrentState := STATE_CAPPING;
        END_IF

    STATE_CAPPING:
        (* Activate capping machine *)
        Capping_Machine := TRUE;
        
        (* Transition to PACKING when capping is confirmed *)
        IF cappingConfirmButton THEN
            CurrentState := STATE_PACKING;
        END_IF

    STATE_PACKING:
        (* Activate packing machine *)
        Packing_Machine := TRUE;
        
        (* Transition to COMPLETED when packing is confirmed *)
        IF packingConfirmButton THEN
            CurrentState := STATE_COMPLETED;
        END_IF

    STATE_COMPLETED:
        (* Light up completion indicator *)
        Completion_Light := TRUE;
        
        (* Transition to IDLE when bottle is picked up *)
        IF finishedButton THEN
            CurrentState := STATE_IDLE;
        END_IF

END_CASE